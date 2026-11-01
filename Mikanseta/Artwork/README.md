# Mikanseta app icon

`AppIcon.png` is the single opaque 1024 × 1024 source for Mikanseta's iOS, macOS, Android, and Windows icons. It keeps the girl, outline, headphones, ahoge, check hair clip, collar, and framing from `../../App/Artwork/AppIconSource.png`, with one gentle wink and a small, friendly asymmetric smile. Its final color revision slightly lightens the green background and outlines and brightens the cream areas. The native Mikansei icon source is not changed.

The expression edit used the built-in `image_gen` tool with the native Mikansei icon as its edit target. The final color revision used the current Mikanseta icon as its edit target. The generated 1254 × 1254 opaque PNG was resized to 1024 × 1024 with `sips`. Platform sizes are exported with `python3 Scripts/generate-icons.py`; it reads `Artwork/AppIcon.png` by default and never calls the older Swift drawing generator. `sips` creates the iOS, macOS, Android, and ICO PNG frames. The Windows `.ico` is assembled from those resized PNG frames without redrawing the image.

To regenerate platform resources after replacing the source:

```sh
python3 Scripts/generate-icons.py
```

The script checks that the source is exactly 1024 × 1024 and has no alpha channel. iOS and macOS sizes come from their `Contents.json` catalogs; Android uses mdpi, hdpi, xhdpi, xxhdpi, and xxxhdpi. Windows includes 16, 24, 32, 48, 64, 128, and 256 pixel frames.

## Expression-change prompt

> Use case: precise-object-edit
> Asset type: square mobile and desktop app icon
> Primary request: Edit the supplied native Mikansei app icon so the same girl has a friendly, playful, slightly mischievous expression.
> Input images: Image 1 is the sole edit target and identity reference. Preserve this exact illustrated girl and use no other references.
> Scene/backdrop: same solid deep green full-bleed square background.
> Subject: preserve the same cream-colored long-haired girl, headphones, single curved ahoge, small green check hair clip, face shape, collar, framing, scale, and centered composition. Change only her expression: give her one gently narrowed / lightly winking eye, leave the other eye open and relaxed, and replace the tiny straight mouth with a small asymmetrical sly smile. The expression should read as warm, friendly, and playful, never sarcastic or mean.
> Style/medium: clean, flat, logo-like vector-style illustration; broad simple shapes, crisp edges, few colors, matching the source art.
> Composition/framing: 1024 by 1024 square, same close-up and placement as the source, image fills the canvas edge to edge.
> Color palette: retain the source deep green, cream, muted mint, and dark green palette.
> Constraints: preserve the character silhouette, hair, headphones, ahoge, check hair clip, outfit collar, palette, and overall composition. Opaque background. No rounded frame or border; the operating system applies the icon mask.
> Avoid: text, lettering, new objects, props, extra details, additional characters, photorealism, complex anime shading, gradients, watermark, asymmetrical framing, changing the girl's identity or hairstyle.

## Final color-revision prompt

> Use case: precise-object-edit
> Asset type: square mobile and desktop app icon
> Primary request: Make the supplied Mikanseta app icon overall a little lighter, softer, and airier, at a moderate roughly 15% adjustment.
> Input images: Image 1 is the sole edit target. Preserve its exact illustrated character and design.
> Scene/backdrop: same full-bleed solid green square background.
> Subject: the same cream-colored girl with headphones, ahoge, check hair clip, gently winking eye, small playful smile, long hair, and collar.
> Style/medium: preserve the existing clean, flat, logo-like illustration with crisp, simple shapes and few colors.
> Composition/framing: preserve the exact square full-bleed framing, scale, centered composition, silhouette, facial expression, hair, headphones, ahoge, hair clip, collar, and linework.
> Color palette: only lighten the green background and deep green outlines by about 15%, making them softer and less dark while maintaining clear contrast and the original green family. Brighten the cream areas slightly. Keep all colors within the existing green, cream, and muted mint palette.
> Constraints: perform a color-value adjustment only; keep every shape, edge, line, detail, and position unchanged. Opaque square image filling the canvas, no transparency.
> Avoid: changing the face or expression, changing linework or character identity, adding decoration or objects, new colors, gradients, texture, text, border, rounded corners, watermark, or any composition change.
