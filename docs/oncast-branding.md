# Oncast branding

Oncast is developed by Sang Yeop Lim. Its app UI, privacy prompts, client labels and copied
deeplinks use Oncast. About links to byyeop.com, the personal fork and its Issues; Support
opens ko-fi.com/yeopmac. Original copyright is preserved in LICENSE and bundled NOTICE.

`com.gityeop.tinycast`, the `.tinycast` backup format and existing data locations remain
unchanged. New copied links use `oncast://`; existing `tinycast://` URLs are still accepted. Renaming the app does not require moving preferences or editing Leader Key URLs.

## Icon source

The production artwork is [Oncast.png](../Tinycast/oncast.icon/Assets/Oncast.png).
Icon Composer compiles [oncast.icon](../Tinycast/oncast.icon) with glass and translucency disabled
to keep the white O and cyan/magenta glitch edges crisp. macOS supplies the rounded mask.

The artwork was generated and normalized with the built-in `imagegen` tool.
The selected concept is a white geometric O with two horizontal glitch cuts on dark graphite,
with no lightning or wordmark. The final image-edit prompt was:

> Use case: precise-object-edit. Asset: production square macOS app icon artwork. Edit target is
> the approved image. Keep the EXACT existing white geometric O, two glitch slice displacements,
> crisp cyan left and magenta right fringe, material and restrained glow unchanged. Change ONLY
> the background framing: remove the exterior gray mockup backdrop, rounded tile outline, bevel
> and drop shadow. The dark graphite surface should extend smoothly to EVERY edge and EVERY
> corner of the square canvas, full bleed; the operating system will provide the rounded mask.
> Keep the O centered at its existing 64% canvas width and 59% height, do not enlarge it. The
> graphite backdrop must be clean and subtle, no new texture. This is an export normalization,
> NOT a new logo. No added text, lightning or new glitches. Do not introduce rough, noisy,
> chipped, frayed, speckled edges. Preserve the pristine solid geometry of the approved O and
> original color balance.

Export a native macOS preview with Icon Composer's `ictool`:

```sh
"/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Tinycast/oncast.icon --export-image --output-file /absolute/path/Oncast-icon.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```
