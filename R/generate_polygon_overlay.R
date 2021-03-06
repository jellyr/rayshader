#'@title Generate Polygon Overlay
#'
#'@description Calculates and returns an overlay of contour lines for the current height map.
#'
#'@param geometry An `sf` object with POLYGON geometry.
#'@param extent A `raster::Extent` object with the bounding box for the height map used to generate the original map.
#'@param heightmap Default `NULL`. The original height map. Pass this in to extract the dimensions of the resulting 
#'overlay automatically.
#'@param width Default `NA`. Width of the resulting overlay. Default the same dimensions as height map.
#'@param height Default `NA`. Width of the resulting overlay. Default the same dimensions as height map.
#'@param linecolor Default `black`. Color of the lines.
#'@param palette Default `black`. Single color, named vector color palette, or palette function. 
#'If this is a named vector and `data_column_fill` is not `NULL`, 
#'it will map the colors in the vector to the names. If `data_column_fill` is a numeric column,
#'this will give a continuous mapping.
#'@param linewidth Default `1`. Line width.
#'@param data_column_fill Default `NULL`. The column to map the polygon fill color. If numeric
#'@return Semi-transparent overlay with contours.
#'@export
#'@examples
#'#Plot the counties around Monterey Bay, CA
#'\donttest{
#'generate_polygon_overlay(monterey_counties_sf, palette = rainbow, 
#'                         extent = attr(montereybay,"extent"), heightmap = montereybay) %>%
#'  plot_map() 
#'
#'#These counties include the water, so we'll plot bathymetry data over the polygon
#'#data to only include parts of the polygon that fall on land.
#'water_palette = colorRampPalette(c("darkblue", "dodgerblue", "lightblue"))(200)
#'bathy_hs = height_shade(montereybay, texture = water_palette)
#'
#'generate_polygon_overlay(monterey_counties_sf, palette = rainbow, 
#'                         extent = attr(montereybay,"extent"), heightmap = montereybay) %>%
#'  add_overlay(generate_altitude_overlay(bathy_hs, montereybay, start_transition = 0)) %>%
#'  plot_map()
#'
#'#Add a semi-transparent hillshade and change the palette, and remove the polygon lines
#'montereybay %>%
#'  sphere_shade(texture = "bw") %>%
#'  add_overlay(generate_polygon_overlay(monterey_counties_sf, 
#'                         palette = terrain.colors, linewidth=NA,
#'                         extent = attr(montereybay,"extent"), heightmap = montereybay),
#'                         alphalayer=0.7) %>%
#'  add_overlay(generate_altitude_overlay(bathy_hs, montereybay, start_transition = 0)) %>%
#'  add_shadow(ray_shade(montereybay,zscale=50),0) %>%
#'  plot_map()
#'
#'#Map one of the variables in the sf object and use an explicitly defined color palette
#'county_palette = c("087" = "red",    "053" = "blue",   "081" = "green", 
#'                   "069" = "yellow", "085" = "orange", "099" = "purple") 
#'montereybay %>%
#'  sphere_shade(texture = "bw") %>%
#'  add_shadow(ray_shade(montereybay,zscale=50),0) %>%
#'  add_overlay(generate_polygon_overlay(monterey_counties_sf, linecolor="white", linewidth=3,
#'                         palette = county_palette, data_column_fill = "COUNTYFP",
#'                         extent = attr(montereybay,"extent"), heightmap = montereybay),
#'                         alphalayer=0.7) %>%
#'  add_overlay(generate_altitude_overlay(bathy_hs, montereybay, start_transition = 0)) %>%
#'  add_shadow(ray_shade(montereybay,zscale=50),0.5) %>%
#'  plot_map()
#'}
generate_polygon_overlay = function(geometry, extent, heightmap = NULL, 
                                    width=NA, height=NA, data_column_fill = NULL, 
                                    linecolor = "black", palette = "white", linewidth = 1) {
  if(!("sf" %in% rownames(utils::installed.packages()))) {
    stop("{sf} package required for generate_line_overlay()")
  }
  if(is.null(extent)) {
    stop("`extent` must not be NULL")
  }
  stopifnot(!is.null(heightmap) || (!is.na(width) && !is.na(height)))
  stopifnot(!missing(extent))
  stopifnot(!missing(geometry))
  if(!inherits(geometry,"sf")) {
    stop("geometry must be {sf} object")
  }
  sf_contours_cropped = base::suppressMessages(base::suppressWarnings(sf::st_crop(geometry, extent)))
  
  if(is.na(height)) {
    height  = ncol(heightmap)
  }
  if(is.na(width)) {
    width  = nrow(heightmap)
  }
  if (is.function(palette)) {
    palette = palette(nrow(sf_contours_cropped))
  }
  if(is.function(palette)) {
    transparent = FALSE
  } else if(length(palette) == 1 && is.na(palette[1])) {
    transparent = TRUE
  } else {
    transparent = FALSE
  }
  if(!transparent) {
    #Calculate colors
    stopifnot(is.character(palette))
    if(!is.null(data_column_fill)) {
      if(data_column_fill %in% colnames(sf_contours_cropped)) {
        if(is.numeric(sf_contours_cropped[[data_column_fill]])) {
          max_col = max(sf_contours_cropped[[data_column_fill]],na.rm = TRUE)
          min_col = min(sf_contours_cropped[[data_column_fill]],na.rm = TRUE)
          indices = (sf_contours_cropped[[data_column_fill]] - min_col) / (max_col - min_col) * length(palette)
          fillvals = palette[as.integer(indices)]
        } else if (is.character(sf_contours_cropped[[data_column_fill]])) {
          mapping = names(palette)
          indices = match(sf_contours_cropped[[data_column_fill]],mapping)
          fillvals = palette[as.integer(indices)]
        } else if  (is.factor(sf_contours_cropped[[data_column_fill]])) {
          character_col = as.character(sf_contours_cropped[[data_column_fill]])
          mapping = names(palette)
          indices = match(sf_contours_cropped[[data_column_fill]],mapping)
          fillvals = palette[as.integer(indices)]
        }
      } else {
        warning("Was not able to find data_column_fill `", data_column_fill, "` in {sf} object.")
        fillvals = palette
      }
    } else {
      if(nrow(sf_contours_cropped) %% length(palette) != 0) {
        stop("Number of explicitly defined colors does not match (or recycle within) number of polygons")
      }
      fillvals = palette
    }
  }
  if(linewidth == 0 || is.na(linewidth)) {
    lty = "blank"
    linewidth=10
  } else {
    lty = "solid"
  }
  tempoverlay = tempfile(fileext = ".png")
  grDevices::png(filename = tempoverlay, width = width, height = height, units="px",bg = "transparent")
  graphics::par(mar = c(0,0,0,0))
  if(!transparent) {
    graphics::plot(sf::st_geometry(sf_contours_cropped), xlim = c(extent@xmin,extent@xmax),
                   ylim =  c(extent@ymin,extent@ymax), 
                   lty = lty, border = NA, asp = 1,
                   xaxs = "i", yaxs = "i", lwd = linewidth, col = fillvals)
  }
  if(!is.na(linewidth) && linewidth > 0) {
    graphics::plot(sf::st_geometry(sf_contours_cropped), xlim = c(extent@xmin,extent@xmax), 
                   ylim =  c(extent@ymin,extent@ymax),
                   lty = lty, add=!transparent, asp = 1,
                   xaxs = "i", yaxs = "i", lwd = linewidth, col = NA, border = linecolor)
  }
  grDevices::dev.off() #resets par
  png::readPNG(tempoverlay)
}