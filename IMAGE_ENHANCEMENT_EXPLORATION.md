# Image Enhancement Exploration

**Status: exploratory — none of this is applied to shipped content.** This note records
options (and dead ends) for making body surface maps look better at close range, captured
while developing `shaders/depixelation.gdshader` against the Moon. It exists to steer a
future effort, not to document current behavior. The only thing actually shipped is
`depixelation.gdshader`, which does bicubic resampling and nothing else.

### Background: the Moon effort

A fixed-resolution global map (the Moon ships a 4096 albedo and a 2048 normal) shows blocky
texel "squares" when magnified from orbital range, and a smooth upscale that removes the
blocks then looks soft. What we learned trying to do better:

- **Bicubic de-pixelation is the clear, cheap win** and is all `depixelation.gdshader` does.
  Resampling albedo and normal C2-continuously removes the texel squares. Keep it minimal.
- **Content-blind synthesis (FBM "relief" / grain) actively harms the image.** Procedural
  noise added uniformly reads as a rubble pile *everywhere*. That is fine where the surface
  *is* rubble, but it roughens naturally smooth regions (maria) and fights continuous real
  features (crater rims, impact rays, and on other bodies linear cracks such as Europa's
  lineae). Uncorrelated detail cannot sharpen real structure; it can only damage it.
- **Unsharp-mask sharpening helps only marginally, and not on the Moon.** Sharpening
  *redistributes* existing information (good in principle — it enhances real features instead
  of inventing). But the Moon's narrow albedo palette offers little to work with: maria are
  harmed by any albedo sharpening at all (it amplifies compression noise in a flat region),
  terrae tolerate only ~0.3 before halos appear. Net gain too small to justify. (Normal-map
  sharpening fares a little better, since relief carries more contrast than color.)
- **Key insight for any future synthesis:** real features (craters, streaks, cracks) are
  *continuous over many pixels* — a small crater stays recognizable even in a blurry 10×10
  patch, because its structure lives in the low frequencies that survive blurring. So the
  useful question is not "add detail" but "read the existing structure and treat flats,
  edges, and rough areas differently."

The two productive directions follow.

### 1. Enhancing the existing image (offline)

Start from the highest-resolution source available (for the Moon: LROC WAC/NAC mosaics for
albedo, LOLA DEM for relief — both far higher-res than what is shipped) and pre-process it
*once* into a better map that is simply shipped or streamed:

- **Super-resolution.** Classical edge-directed methods (NEDI, Lanczos) for a safe 2×, or ML
  upscalers (Real-ESRGAN, diffusion upscalers) for more. Derive the normal map from a
  super-res'd height/DEM rather than upscaling the normal directly.
- **Why offline beats anything per-frame:** unlimited iterations, no frame budget, a real
  learned prior, and the output is just a cached texture. Anything a shader can do per
  fragment, an offline pass does better and once.
- **Caveats.** ML upscalers *hallucinate* — for planetary/scientific content, hand-verify
  they don't invent false craters or smear real ones. Final resolution is still capped by
  VRAM and (for the PWA) download size, which is the real reason to also weigh the
  procedural route below.

### 2. Structure-guided (content-adaptive) synthesis by shader

If detail must be generated on the fly (infinite zoom, or a body with no better map), make
it *conditioned on the local image* instead of uniform:

- **The structure tensor** is the cheap enabling tool: average the outer product of the local
  gradient over a few taps; its closed-form 2×2 eigen-solution gives, per fragment, *energy*
  (flat vs. feature), *coherence* (line-like vs. isotropic), and *orientation*. On the Moon,
  compute it from the **normal map, not the albedo** — the normal *is* the surface gradient,
  so it carries structure exactly where the color palette is poor.
- **Three regimes fall out, matching the taxonomy above:**
  - *Flat (maria):* energy ≈ 0 → add nothing; optionally a gentle denoise/blur (maria
    actually benefit from slight smoothing).
  - *Oriented (rims, rays, lineae):* high coherence → steer the operator *along* the feature
    and sharpen *across* it (a shock-filter step turns a blurry ramp into a crisp edge with no
    halo), keeping continuous features continuous.
  - *Isotropic-rough (rubble):* high energy, low coherence → isotropic procedural detail is
    fine here — rubble only where there's already rubble.
- **Use a steerable primitive:** Gabor / flow noise (orientable) rather than isotropic FBM,
  so invented micro-detail runs parallel to the structure.
- **Cost / passes.** Structure tensor + eigen is cheap; a strong shock/denoise wants multiple
  iterations (ping-pong passes or a compositor effect — the latter operates on the lit
  framebuffer and affects everything), whereas a single in-material pass buys one weak
  iteration. Gate all of it to magnified views (texels-per-pixel), off at the limb where UV
  derivatives explode.
- **Honest ceiling.** This redistributes and extends information already present; it does not
  *reconstruct* true sub-resolution features (that is hallucination, whose only honest source
  is the offline ML route). Its one legitimate niche is infinite-zoom *generic* texture
  (regolith granularity) where hallucination is acceptable and shipping the pixels is not.

Reading: coherence-enhancing shock filtering (Weickert); structure-adaptive image abstraction
(Kyprianidis & Döllner, real-time on GPU); flow noise (Perlin & Neyret) and Gabor noise
(Lagae); edge-directed interpolation (NEDI) and joint-bilateral upsampling.
