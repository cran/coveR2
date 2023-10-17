# coveR 1.0.0

* Added a `NEWS.md` file to track changes to the package.

The package has been re-structured:

* It uses `terra` instead of `raster`
* a single function `coveR` allows to perform all the processing steps:
  1. importing images
  2. making binary images of gaps and canopy
  3. classifying gaps based on size
  4. applying theoretical formulas relating canopy to gap fraction
* EXIF functionality now uses native R functions from package `EXIFr` avoiding third-party software or C libraries
* Segmentation uses a function from CRAN's `mgc`package


