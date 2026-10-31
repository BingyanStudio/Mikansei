#!/usr/bin/env python3
"""Attach shared native core and independently named Flutter extensions, preserving signing."""
from pathlib import Path
import hashlib,json,subprocess,plistlib
ROOT=Path(__file__).resolve().parents[2]
MKS=ROOT/'Mikanseta'
version_line=next(line for line in (MKS/'pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
version_value=version_line.partition(':')[2].strip()
widget_marketing_version, version_separator, widget_build_number=version_value.partition('+')
if not version_separator:
 widget_build_number='1'
def uid(s):return hashlib.sha1(('Mikanseta.port.'+s).encode()).hexdigest()[:24].upper()
def atom(v):
 if isinstance(v,dict):return '{\n'+'\n'.join(json.dumps(str(k))+ ' = '+atom(x)+';' for k,x in v.items())+'\n}'
 if isinstance(v,list):return '(\n'+''.join(atom(x)+',\n' for x in v)+')'
 return json.dumps(str(v))
def configure(platform):
 file=MKS/platform/('Mikanseta.xcodeproj' if platform=='ios' else 'Runner.xcodeproj')/'project.pbxproj'
 project=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(file)]));objects=project['objects']
 app=next((key for key,value in objects.items() if value.get('isa')=='PBXNativeTarget' and value.get('productType')=='com.apple.product-type.application'))
 target=objects[app];sources=next(objects[k] for k in target['buildPhases'] if objects[k]['isa']=='PBXSourcesBuildPhase');resources=next(objects[k] for k in target['buildPhases'] if objects[k]['isa']=='PBXResourcesBuildPhase')
 main=objects[objects[project['rootObject']]['mainGroup']]
 def addFile(path,phase,tag):
  rel=str(path.relative_to(ROOT));ref=uid('ref'+rel);build=uid(tag+rel)
  typ='audio.wav' if path.suffix=='.wav' else 'sourcecode.swift'
  objects[ref]={'isa':'PBXFileReference','lastKnownFileType':typ,'name':path.name,'path':'../../'+rel,'sourceTree':'SOURCE_ROOT'}
  objects[build]={'isa':'PBXBuildFile','fileRef':ref}
  if build not in phase['files']:phase['files'].append(build)
  return ref
 core=[p for p in (ROOT/'Sources/MikanseiCore').glob('*.swift') if p.stem!='AppRoute']
 files=core+[MKS/'native/Apple/AppleSystemServices.swift']+list((MKS/'native/Apple').glob('Pomodoro*.swift'))
 if platform=='ios':files+=list((MKS/'native/Apple/Ported').glob('*.swift'))
 group=uid(platform+'native-group');objects[group]={'isa':'PBXGroup','name':'Shared Native Services','children':[addFile(p,sources,platform+'app') for p in files],'sourceTree':'<group>'}
 if group not in main['children']:main['children'].append(group)
 for sound in (ROOT/'App/Resources').glob('*.wav'):addFile(sound,resources,platform+'sound')
 configs=[objects[c]['buildSettings'] for c in objects[target['buildConfigurationList']]['buildConfigurations']]
 for cfg in configs:
  if platform=='ios':cfg['CODE_SIGN_ENTITLEMENTS']='Runner/Mikanseta.entitlements'
 if platform=='ios':
  team=next((c['DEVELOPMENT_TEAM'] for c in configs if c.get('DEVELOPMENT_TEAM')),'');bundle=next(c['PRODUCT_BUNDLE_IDENTIFIER'] for c in configs if c.get('PRODUCT_BUNDLE_IDENTIFIER'))
  for c in configs:c['MIKANSETA_SHARED_KEYCHAIN_SUFFIX']=bundle+'.shared'
  w=uid('widgets-target');ws=uid('widgets-sources');wr=uid('widgets-resources');wf=uid('widgets-frameworks');cl=uid('widgets-configs');product=uid('widgets-product')
  objects[ws]={'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':[],'runOnlyForDeploymentPostprocessing':'0'}
  objects[wr]={'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':[],'runOnlyForDeploymentPostprocessing':'0'}
  objects[wf]={'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':[],'runOnlyForDeploymentPostprocessing':'0'}
  widgetFiles=list((MKS/'ios/Widgets').glob('*.swift'))+core+[MKS/'native/Apple/Ported'/f'{p}.swift' for p in ['AppRoute','WidgetSnapshotStore','PomodoroSnapshotStore','DeadlineActivityAttributes','ReminderAlarmMetadata','FocusClock']]
  wg=uid('widgets-group');objects[wg]={'isa':'PBXGroup','name':'Mikanseta Widgets','children':[addFile(p,objects[ws],'widget') for p in widgetFiles],'sourceTree':'<group>'}
  if wg not in main['children']:main['children'].append(wg)
  objects[product]={'isa':'PBXFileReference','explicitFileType':'wrapper.app-extension','path':'MikansetaWidgets.appex','sourceTree':'BUILT_PRODUCTS_DIR','includeInIndex':'0'}
  products=objects[objects[project['rootObject']]['productRefGroup']]
  if product not in products['children']:products['children'].append(product)
  configids=[]
  for name in ['Debug','Release','Profile']:
   c=uid('widgets-'+name);configids.append(c);objects[c]={'isa':'XCBuildConfiguration','name':name,'buildSettings':{'PRODUCT_NAME':'MikansetaWidgets','PRODUCT_BUNDLE_IDENTIFIER':bundle+'.Widgets','DEVELOPMENT_TEAM':team,'CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS':'Runner/Mikanseta.entitlements','MIKANSETA_SHARED_KEYCHAIN_SUFFIX':bundle+'.shared','INFOPLIST_FILE':'Widgets/Info.plist','MARKETING_VERSION':widget_marketing_version,'CURRENT_PROJECT_VERSION':widget_build_number,'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1,2','SWIFT_VERSION':'5.0','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks'],'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O'}}
  objects[cl]={'isa':'XCConfigurationList','buildConfigurations':configids,'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'}
  objects[w]={'isa':'PBXNativeTarget','buildConfigurationList':cl,'buildPhases':[ws,wf,wr],'buildRules':[],'dependencies':[],'name':'MikansetaWidgets','productName':'MikansetaWidgets','productReference':product,'productType':'com.apple.product-type.app-extension'}
  proj=objects[project['rootObject']]
  if w not in proj['targets']:proj['targets'].append(w)
  embed=uid('embed-phase');eb=uid('embed-build');dep=uid('widget-dependency');proxy=uid('widget-proxy')
  objects[eb]={'isa':'PBXBuildFile','fileRef':product,'settings':{'ATTRIBUTES':['RemoveHeadersOnCopy']}}
  objects[embed]={'isa':'PBXCopyFilesBuildPhase','buildActionMask':'2147483647','dstPath':'','dstSubfolderSpec':'13','files':[eb],'name':'Embed Mikanseta Widgets','runOnlyForDeploymentPostprocessing':'0'}
  target['buildPhases']=[p for p in target['buildPhases'] if p!=embed]
  thin=next((i for i,p in enumerate(target['buildPhases']) if objects[p].get('name')=='Thin Binary'),len(target['buildPhases']))
  target['buildPhases'].insert(thin,embed)
  objects[proxy]={'isa':'PBXContainerItemProxy','containerPortal':project['rootObject'],'proxyType':'1','remoteGlobalIDString':w,'remoteInfo':'MikansetaWidgets'}
  objects[dep]={'isa':'PBXTargetDependency','target':w,'targetProxy':proxy}
  if dep not in target['dependencies']:target['dependencies'].append(dep)
 file.write_text('// !$*UTF8*$!\n'+atom(project)+'\n')
 for plist in [MKS/platform/'Runner/Info.plist']:
  with plist.open('rb') as f:info=plistlib.load(f)
  info['NSCalendarsUsageDescription']='读取你选择的日历，将日程与待办放在同一张清单中。'
  info['NSCalendarsFullAccessUsageDescription']='读取所选日历，并在你确认后安排或编辑日历事件。'
  if platform=='ios':
   info['NSAlarmKitUsageDescription']='按事项截止时间、日程或下课时间设置闹钟提醒。';info['NSSupportsLiveActivities']=True
   info['MikansetaSharedKeychainGroup']='$(AppIdentifierPrefix)$(MIKANSETA_SHARED_KEYCHAIN_SUFFIX)'
   info['CFBundleURLTypes']=[{'CFBundleURLName':'com.personal.mikanseta','CFBundleURLSchemes':['mikanseta']}]
   info['FlutterDeepLinkingEnabled']=False
  with plist.open('wb') as f:plistlib.dump(info,f)
configure('ios');configure('macos')
with (MKS/'ios/Runner/Mikanseta.entitlements').open('wb') as f:plistlib.dump({'keychain-access-groups':['$(AppIdentifierPrefix)$(MIKANSETA_SHARED_KEYCHAIN_SUFFIX)']},f)
with (ROOT/'Widgets/Info.plist').open('rb') as f:info=plistlib.load(f)
info={k.replace('Mikansei','Mikanseta'):v.replace('Mikansei','Mikanseta').replace('MIKANSEI','MIKANSETA') if isinstance(v,str) else v for k,v in info.items()}
with (MKS/'ios/Widgets/Info.plist').open('wb') as f:plistlib.dump(info,f)
for name in ['DebugProfile','Release']:
 p=MKS/f'macos/Runner/{name}.entitlements'
 with p.open('rb') as f:ent=plistlib.load(f)
 ent['com.apple.security.personal-information.calendars']=True
 with p.open('wb') as f:plistlib.dump(ent,f)
print('Shared native core and Mikanseta Widgets configured; existing team and app identifiers preserved.')
