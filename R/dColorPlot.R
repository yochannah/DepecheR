#' Display third variable as color on a 2D plot
#'
#'
#' Function to overlay one variable for a set of observations on a field 
#' created by two other variables known for the same observations. The plot is 
#' constructed primarily for displaying variables on 2D-stochastic neighbour 
#' embedding fields, but can be used for any sets of (two or) three variables 
#' known for the same observations. As the number of datapoints is often very 
#' high, the files would, if saved as pdf of another vector based file type 
#' become extremely big. For this reason, the plots are saved as jpeg and no 
#' axes or anything alike are added, to simplify usage in publications.
#' @importFrom gplots rich.colors
#' @importFrom parallel detectCores makeCluster stopCluster
#' @importFrom doSNOW registerDoSNOW
#' @importFrom foreach foreach %dopar%
#' @param colorData A numeric matrix or dataframe or a vector, be it numeric, 
#' charater or factor, that should be used to define the colors on the plot. 
#' @param controlData Optional. A numeric/integer vector or dataframe of values
#' that could be used to define the range of the colorData. If no control data 
#' is present, the function defaults to using the colorData as control data.
#' @param xYData These variables create the field on which the colorData will
#' be displayed. It needs to be a matrix or dataframe with two columns and the
#' same number of rows as the colorData object.
#' @param plotName The name(s) for the plot(s). 'default' returns the column 
#' names of the colorData object in the case this is a dataframe and otherwise 
#' returns the somewhat generic name 'testVariable'. It can be substituted with
#' a string (in the case colorData is a vector) or vector of strings, as long as
#' it has the same length as the number of columns in colorData.
#' @param colorScale This argument controls the colors in the plot. See 
#' \code{\link{dColorVector}} for alternatives.
#' @param densContour If density contours should be created for the plot(s) or
#' not. Defaults to TRUE. If a density object, as generated by dContours, is 
#' included, this will be used instead. 
#' @param title If there should be a title displayed on the plotting field. As 
#' the plotting field is saved a jpeg, this title cannot be removed as an object
#' afterwards, as it is saved as coloured pixels. To simplify usage for 
#' publication, the default is FALSE, as the files are still named, eventhough 
#' no title appears on the plot.
#' @param plotDir If different from the current directory. If specified and 
#' non-existent, the function creates it. If "." is specified, the plots will be
#' saved at the current directory. By default, a new directory is added if the
#' created plots will be more than 1.
#' @param truncate If truncation of the most extreme values should be performed
#' for the visualizations. Three possible values: TRUE, FALSE, and a vector 
#' with two values indicating the low and high threshold quantiles for 
#' truncation.
#' @param bandColor The color of the contour bands. Defaults to black.
#' @param dotSize Simply the size of the dots. The default makes the dots 
#' maller the more observations that are included.
#' @param multiCore If the algorithm should be performed on multiple cores. 
#' This increases the speed if the dataset is medium-large (>100000 rows) and 
#' has at least 5 columns. Default is TRUE when the rows exceed 100000 rows and
#' FALSE otherwise.
#' @param nCores If multiCore is TRUE, then this sets the number of parallel 
#' processes. The default is currently 87.5 percent with a cap on 10 cores, as 
#' no speed increase is generally seen above 10 cores for normal computers. 
#' @param createOutput For testing purposes. Defaults to TRUE. If FALSE, no 
#' plots are generated.
#' @seealso \code{\link{dDensityPlot}}, \code{\link{dResidualPlot}}, 
#' \code{\link{dWilcox}}, \code{\link{dColorVector}}
#' @return Plots showing the colorData displayed as color on the field created 
#' by xYData.
#' @examples
#' 
#' # Load some data
#' data(testData)
#' 
#' \dontrun{
#' # Run Barnes Hut tSNE on this. For more rapid example execution, a pre-run
#' # SNE is inluded
#' # library(Rtsne)
#' # testDataSNE <- Rtsne(testData[,2:15], pca=FALSE)
#' data(testDataSNE)
#' 
#' # Run the function for two of the variables
#' dColorPlot(colorData = testData[2:3], xYData = testDataSNE$Y)
#'
#' # Now each depeche cluster is plotted separately and together.
#' 
#' # Run the clustering function. For more rapid example execution,
#' # a depeche clustering of the data is included
#' # testDataDepeche <- depeche(testData[,2:15])
#' data(testDataDepeche)
#' 
#' dColorPlot(colorData = testDataDepeche$clusterVector, 
#'     xYData = testDataSNE$Y, plotName = 'clusters')
#' }
#' @export dColorPlot
dColorPlot <- function(colorData, controlData, xYData, 
                       colorScale = "rich_colors", plotName = "default",
                       densContour = TRUE, title = FALSE, plotDir = "default", 
                       truncate = TRUE, bandColor = "black", 
                       dotSize = 500/sqrt(nrow(xYData)), multiCore = "default",
                       nCores="default", createOutput = TRUE) {

    if (is.matrix(colorData)) {
        colorData <- as.data.frame(colorData)
    }

    if (is.matrix(xYData)) {
        xYData <- as.data.frame(xYData)
    }

    if (plotDir == "default") {
        if(is.vector(colorData)){
            plotDir <- "."
        } else {
            plotDir <- paste0("Marker tSNE distributions")
        }
    }
    
    if (plotDir != ".") {
        dir.create(plotDir)
    }
    
    if(plotName == "default"){
        plotName <- if(is.data.frame(colorData)){
            plotName <- colnames(colorData)
        } else {
            plotName <- "Ids"
        }
    }
    
    if (missing(controlData)) {
        controlData <- colorData
    }
    
    # Create the density matrix for xYData.
    if (is.logical(densContour)) {
        if (densContour) {
            densContour <- dContours(xYData)
        }
    }
    
    if (is.vector(colorData)) {
        if(is.character(colorData)){
            colorData <- as.factor(colorData)
        }
        if(is.factor(colorData)){
            colorData <- as.numeric(colorData)
        }
        if(length(unique(colorData))>50){
            colorDataRound <- round(dScale(colorData, control = controlData,
                                      scale = c(0, 1), robustVarScale = FALSE, 
                                      center = FALSE, multiplicationFactor = 50, 
                                      truncate = truncate))
        } else {
            colorDataRound <- colorData
        }
        
        uniqueIds <- sort(unique(colorDataRound))

        colorVector <- dColorVector(colorDataRound, colorOrder = uniqueIds, 
                                    colorScale = colorScale)
        
        dPlotCoFunction(colorVariable = colorVector, plotName = plotName, 
                            xYData = xYData, title = title, 
                            densContour = densContour, bandColor = bandColor, 
                            dotSize = dotSize, plotDir = plotDir, 
                            createOutput = createOutput)
    } else {
        colorDataRound <- round(dScale(x = colorData, control = controlData, 
                                   scale = c(0, 1), robustVarScale = FALSE, 
                                   center = FALSE, multiplicationFactor = 50, 
                                   truncate = truncate))
        colorVectors <- apply(colorDataRound, 2, dColorVector, 
                              colorScale = colorScale, colorOrder = c(0:50))
        if (multiCore == "default") {
            if (nrow(colorData) > 1e+05) {
                multiCore <- TRUE
            } else {
                multiCore <- FALSE
            }
        }
        if (multiCore) {
            if( nCores=="default"){
                nCores <- floor(detectCores()*0.875) 
                if(nCores>10){
                    nCores <- 10
                }
            }
            cl <- makeCluster(nCores, type = "SOCK")
            registerDoSNOW(cl)
            i <- 1
            return_all <- 
                foreach(i = seq_len(ncol(colorVectors)), 
                                    .packages = "DepecheR") %dopar% 
                dPlotCoFunction(
                    colorVariable = colorVectors[,i],
                    plotName = plotName[i], xYData = xYData,
                    title = title, densContour = densContour,
                    bandColor = bandColor, dotSize = dotSize, plotDir = plotDir,
                    createOutput = createOutput)
            stopCluster(cl)

        } else {
            mapply(dPlotCoFunction, 
                   as.data.frame.matrix(colorVectors, stringsAsFactors = FALSE),
                   plotName, MoreArgs = list(xYData = xYData, 
                                          title = title, 
                                          densContour = densContour, 
                                          bandColor = bandColor, 
                                          dotSize = dotSize, plotDir = plotDir,  
                                          createOutput = createOutput))
        }
    }
    #Create a suitable legend for the task
    if (createOutput) {
        if(is.vector(colorData)){
            pdf(file.path(plotDir, paste0(plotName, "_legend.pdf"))) 
        } else {
            pdf(file.path(plotDir, "Color_legend.pdf")) 
        }
        
        if(is.vector(colorData) && length(uniqueIds < 50)){
            colorIdsDataFrame <- data.frame(
                dColorVector(uniqueIds, colorScale = colorScale), uniqueIds, 
                stringsAsFactors = FALSE)
            plot.new()
            legend("center", legend = colorIdsDataFrame[,2], 
                   col = colorIdsDataFrame[,1], cex = 15/length(uniqueIds), 
                   pch = 19)
        } else {
            yname <- "Expression level"
            topText <- "Highly expressed"
            bottomText <- "Not expressed"
            par(fig = c(0.35, 0.65, 0, 1), xpd = NA)
            z <- matrix(seq_len(49), nrow = 1)
            x <- 1
            y <- seq(0, 1, len = 49)
            image(x, y, z, col = dColorVector(seq.int(1,50), 
                                              colorScale = colorScale), 
                  axes = FALSE, xlab = "", ylab = yname)
            axis(2)
            text(1, 1.1, labels = topText, cex = 1.1)
            text(1, -0.1, labels = bottomText, cex = 1.1)
            box()
        }
        dev.off()
    }

}
