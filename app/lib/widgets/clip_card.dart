/// Deterministic varied aspect ratio for a masonry tile (0.72 → 1.5) so a
/// packed skeleton grid has the same Pinterest/RenderForest "no white space"
/// staggered look as the real tiles it's standing in for.
double masonryAspect(String id) {
  const ratios = [0.72, 0.8, 1.0, 1.33, 0.66, 1.0, 0.8, 1.2];
  return ratios[id.hashCode.abs() % ratios.length];
}
