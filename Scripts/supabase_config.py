"""Read only public Supabase client configuration; never accept admin keys."""
import base64
import json
import plistlib
import re
from pathlib import Path
from urllib.parse import urlparse


RESOURCE_PATH = Path("Configuration/SupabaseClient.plist")
PUBLIC_RESOURCE_PATH = Path("Configuration/SupabaseClient.public.plist")
URL_KEY = "MikanseiSupabaseURL"
CLIENT_KEY = "MikanseiSupabaseAnonKey"


def validate_client_configuration(values):
    url = values.get(URL_KEY, values.get("SUPABASE_URL", ""))
    key = values.get(CLIENT_KEY, values.get("SUPABASE_ANON_KEY", ""))
    if not isinstance(url, str) or not isinstance(key, str):
        raise ValueError("Supabase 客户端配置必须是字符串。")
    url, key = url.strip().rstrip("/"), key.strip()
    if not url and not key:
        return None
    parsed = urlparse(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in ("", "/")
    ):
        raise ValueError("Supabase 项目地址必须是有效的 HTTPS 根地址。")
    if re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]+", key):
        return {URL_KEY: url, CLIENT_KEY: key}
    # Legacy anon JWTs are public client credentials. Service-role JWTs and
    # modern sb_secret_ keys must never enter an application or handoff.
    try:
        pieces = key.split(".")
        if len(pieces) != 3:
            raise ValueError()
        payload = pieces[1]
        role = json.loads(
            base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
        ).get("role")
    except (ValueError, TypeError, UnicodeError, AttributeError):
        role = None
    if role != "anon":
        raise ValueError("只允许 Supabase publishable 或 anon 客户端密钥。")
    return {URL_KEY: url, CLIENT_KEY: key}


def read_env(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:]
        name, separator, value = line.partition("=")
        if separator and name.strip() in ("SUPABASE_URL", "SUPABASE_ANON_KEY"):
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            values[name.strip()] = value
    return values


def load_client_configuration(root):
    root = Path(root)
    resource = root / RESOURCE_PATH
    if resource.is_file():
        with resource.open("rb") as handle:
            return validate_client_configuration(plistlib.load(handle))
    for relative in ("LocalInstall/supabase.env", "Mikanseta/LocalInstall/supabase.env"):
        path = root / relative
        if path.is_file():
            return validate_client_configuration(read_env(path))
    public_resource = root / PUBLIC_RESOURCE_PATH
    if public_resource.is_file():
        with public_resource.open("rb") as handle:
            return validate_client_configuration(plistlib.load(handle))
    return None


def write_client_resource(root, configuration=None):
    root = Path(root)
    if configuration is None:
        configuration = load_client_configuration(root)
    if configuration is None:
        return None
    configuration = validate_client_configuration(configuration)
    if configuration is None:
        return None
    destination = root / RESOURCE_PATH
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as handle:
        plistlib.dump(configuration, handle, sort_keys=True)
    return destination
