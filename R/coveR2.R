#' @name coveR2
#' @aliases coveR2
#'
#' @importFrom terra rast plot nlyr values classify ext crop set.names set.ext set.crs crs
#' @importFrom autothresholdr auto_thresh
#' @importFrom mgc ConnCompLabel
#' @importFrom dplyr mutate group_by summarise select relocate case_match ungroup case_when left_join pull distinct
#' @importFrom lubridate day month year
#' @importFrom jpeg writeJPEG

#' @title Estimate canopy attributes from a cover image, and export the output image
#'
#' @description
#' The function calculates all the image processing steps and
#' returns the output canopy attributes. It is also possible to export the classified image.
#' @param filename Character. The input image filename
#' @param channel Integer. The band number corresponding to the blue channel. Default value is 3
#' @param thdmethod Character. The method used to threshold the image, using the [autothresholdr::auto_thresh()] function. For details, see <https://imagej.net/plugins/auto-threshold>. Default = 'Otsu'.
#' @param gapmethod Character. The method used to classify large and small gaps. Default = 'macfarlane'
#' @param thd Numeric. The large gap threshold, as a function of the image size. Used only when method = 'macfarlane'. Default = 1.3/100
#' @param k Numeric The extinction coefficient at the zenith. Default is 0.5 (spherical leaf angle distribution)
#' @param crop Integer. The number of lines to be removed from the bottom side of the image. Useful to remove the 'timestamp' watermark in camera traps.
#' @param export.image Logical. It allows exporting an image of the classified gaps
#' @param display Logical. It allows displaying the result of image classification.
#' @param message Logical. It allows displaying messages.
#'
#' @examples
#' image <- file.path(system.file(package='coveR2'), 'extdata/IMG1.JPG')
#' res<-coveR2(image, gapmethod='macfarlane',thd=0.5/100, k=0.65)
#' res

#' @export

coveR2 <- function(filename,
                   channel = 3,
                   thdmethod='Otsu',
                   gapmethod = 'macfarlane',
                   thd = 1.3/100,
                   k=0.5,
                   crop=NULL,
                   export.image=FALSE,
                   display=TRUE,
                   message=TRUE) {

#visible binding:
CC<-CP<-FC<-GF<-Le<-L<-NULL
gL<-gMN<-gN<-gSD<-gSE<-NULL
id<-Camera<-CreateDate<-ImageSize<-Model<-NULL
Large_gap<-Small_gap<-Canopy<-Var1<-Freq<-NR<-NULL

#open_blue() part:----
if(!is.numeric(channel)){
  stop('Select a numeric channel band.')
}

mxk <- suppressWarnings({

  if(terra::nlyr(terra::rast(filename))<channel){
    channel=terra::nlyr(terra::rast(filename))

  if(message==TRUE){
     message(paste0('The number of bands is lower than selected channel. The selected channel is set to ',terra::nlyr(terra::rast(filename))))
  }
  }
img <- terra::rast(x = filename, lyrs = channel)
base::names(img) <- basename(filename)
}
)

if(!is.null(crop)&is.numeric(crop)){
    ext<-terra::ext(img)
    ext[3]<-crop
    img<-terra::crop(img,ext)
  }

if(!is.null(crop)&!is.numeric(crop)){
    stop('Provide a numeric value to crop image')
  }

FileSize<- file.info(filename)$size
# Camera<-Model<-ImageSize<-Date<-day<-month<-year<-NA

#thd_blue() part:----
if(terra::nlyr(img)>1){
  stop("Error: the function needs a single channel image")
}

myimg.mat <- matrix(terra::values(img, format='matrix'), ncol=ncol(img))

th <- autothresholdr::auto_thresh(round(myimg.mat), method=thdmethod, ignore_na = TRUE)
th <- as.numeric(unlist(th))
myimg.rst <- terra::classify(img, rbind(c(-Inf,th,0),c( th,Inf,1)))
terra::set.crs(myimg.rst, terra::crs(img))
terra::set.ext(myimg.rst, terra::ext(img))
terra::set.names(myimg.rst, base::names(img))

if (display==TRUE){
    terra::plot(myimg.rst,col=c('black','white'),main=paste('binarized',thdmethod,th,sep='_'), legend=FALSE)
}


#label_gaps():----
vals <- matrix(terra::values(myimg.rst,format='matrix'),nrow = nrow(myimg.rst),byrow=T)
y <- mgc::ConnCompLabel(vals)
yr <- terra::rast(nrows = nrow(myimg.rst), ncols=ncol(myimg.rst),vals=y)
ext <- terra::ext(myimg.rst)
terra::set.ext(yr, ext)
terra::set.names(yr, base::names(myimg.rst))
# terra::plot(yr)
# base::names(yr) <- base::names(myimg.rst)

tbr <- data.frame(base::table(terra::values(yr)))

#extract_gap():----
if(length(setdiff(gapmethod, c('alivernini', 'macfarlane')))>0){
  stop("Error: method must be one element between 'alivernini' or 'macfarlane'")
}


if (gapmethod=='alivernini') {
gTHD <- tbr |>
  dplyr::mutate(NR=sum(Freq)) |>
  dplyr::filter(Var1!="0") |> #stats calculated only on gaps
  dplyr::mutate(gMN=mean(Freq),
         gSD=stats::sd(Freq),
         gN=max(dplyr::row_number()),
         gSE=gSD/sqrt(gN)) |>
  dplyr::mutate(gTHD=gMN+gSE) |>
  dplyr::distinct(gTHD) |>
  dplyr::pull(gTHD)

tbf <- tbr |>
  dplyr::mutate(id=base::names(yr)) |>
  dplyr::mutate(NR=sum(Freq)) |>
  dplyr::mutate(gL=dplyr::case_when(
          Var1=='0'~'Canopy',
          Freq>=gTHD & Var1!="0"~'Large_gap',
          TRUE~'Small_gap'))
}


if (gapmethod=='macfarlane'){
tbf <- tbr |>
  dplyr::mutate(id=base::names(yr)) |>
  dplyr::mutate(NR=sum(Freq)) |>
  dplyr::mutate(gL=dplyr::case_when(
    Var1=='0'~ 'Canopy',
    Freq>=NR*thd & Var1!='0' ~ 'Large_gap',
    TRUE~ 'Small_gap'
  ))
}

tbf.sum <- tbf |>
  dplyr::group_by(gL) |>
  dplyr::summarise(Freq=sum(Freq/NR)) |>
  tidyr::pivot_wider(names_from=gL,values_from=Freq)



# #get_canopy():----
if(k > 1){
  if(message==TRUE){
  warning(paste0("The extinction coefficient (k) was set to ",
                 k,
                 ". It ranges typically between 0.4 and 0.9"))
  }
}
#
if(length(unique(tbf$id)) > 1){
  stop("only a single image per time is allowed")
  }

canopy <- tbf.sum |>
  dplyr::mutate(ncol=ncol(tbf.sum),
         GF=1-Canopy,
         FC=Canopy) |>
  dplyr::mutate(Large_gap=dplyr::case_when(
    ncol<3~0,
    TRUE~1-(Canopy+Small_gap)
  )) |>
  dplyr::select(-ncol) |>
  dplyr::mutate(
    id=base::names(yr),
    CC=1-Large_gap,
    CP=1-(FC/CC),
    Le=-log(1-FC)/k,
    L=-CC*log(CP)/k,
    CI=Le/L,
    k=k
    ) |>
  dplyr::select(-c(GF,Canopy,Small_gap,Large_gap)) |>
  dplyr::mutate(
    imgchannel=channel,
    gapmethod=gapmethod,
    imgmethod=thdmethod,
    thd=thd
  ) |>
  dplyr::relocate(id)


#exporting image:----
if (export.image==TRUE){
tbf.new <- tbf  |>
    dplyr::ungroup()  |>
    dplyr::mutate(col=dplyr::case_match(
      gL,
      'Large_gap'~0.5,
      'Small_gap'~1,
      'Canopy'~0)
      ) |>
    dplyr::select(Var1, col) |>
    dplyr::mutate(Var1=as.integer(as.character(Var1)))
#
canopy.rst <- terra::classify(yr, as.matrix(tbf.new))
terra::set.crs(canopy.rst, terra::crs(img))
terra::set.names(canopy.rst, base::names(yr))
terra::set.ext(canopy.rst, ext)
# terra::plot(canopy.rst)

dir.create(base::file.path(base::getwd(), 'results'), showWarnings = FALSE)
jpeg::writeJPEG(matrix(terra::values(canopy.rst),  nrow=nrow(yr), ncol= ncol(yr),byrow=T),
                target=base::paste0(base::file.path(base::getwd()), '/results/class_',base::names(canopy.rst)))

}

canopy.out <- canopy
return(canopy.out)

}
