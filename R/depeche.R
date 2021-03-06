#' Perform optimization and penalized K-means clustering
#'
#'
#' This is the central function of the package. As input, only a dataset is 
#' required. It starts by performing optimizations and then performs clustering 
#' based on the values identified in the optimization step.
#' @importFrom moments kurtosis
#' @importFrom grDevices col2rgb colorRampPalette densCols dev.off palette pdf 
#' png
#' @importFrom graphics axis contour hist image legend mtext par plot plot.new 
#' text
#' @importFrom stats median p.adjust predict quantile rnorm sd var wilcox.test 
#' runif
#' @importFrom utils write.csv tail
#' @importFrom methods is
#' @param inDataFrame A dataframe or matrix with the data that will be used to 
#' create the clustering. Cytometry data should be transformed using 
#' biexponential, arcsinh transformation or similar, and day-to-day 
#' normalizations should to be performed for all data if not all data has been 
#' acquired on the same run. Scaling, etc, is on the other hand performed 
#' within the function.
#' @param penalties This argument decides whether a single penalty will be used 
#' for clustering, or if multiple penalties will be evaluated to identify the 
#' optimal one. A single value, a vector of values, or possibly a list of two 
#' vectors, if dual clustering is performed can be given here. The suggested 
#' default values are empirically defined and might not be optimal for a 
#' specific dataset, but the algorithm will warn if the most optimal values are 
#' on the borders of the range. Note that when the penalty is 0, there is no 
#' penalization, which means that the algorithm runs standard K-means 
#' clustering.
#' @param sampleSize This controls what fraction of the dataset that will be 
#' used to run the penalty optimization. 'default' results in the full file in 
#' files up to 10000 events. In cases where the sampleSize argument is larger 
#' than 10000, default leads to the generation of a random subset to the same 
#' size also for the selectionSampleSize. A user specified number is also 
#' accepted.
#' @param selectionSampleSize The size of the dataset used to find the optimal 
#' solution out of the many generated by the penalty optimization at each sample
#' size. 'default' results in the full file in files up to 10000 events. In 
#' cases where the sampleSize argument is larger than 10000, default leads to 
#' the generation of a random subset to the same size also for the 
#' selectionSampleSize. A user specified number is also accepted.
#' @param dualDepecheSetup Optionally, a dataframe with two columns: the first 
#' specifying which step (1 or 2) the variable should be included in, the second
#' specifying the column name for the variable in question. It is used if a 
#' two-step clustering should be performed, e.g. in the case where phenotypic 
#' clustering should be performed, followed by clustering on functional 
#' variables.
#' @param k Number of initial cluster centers. The higher the number, the 
#' greater the precision of the clustering, but the computing time also 
#' increases linearly with the number of starting points. Default is 30. If 
#' penalties=0, k-means clustering with k clusters will be performed.
#' @param minARIImprovement This is the stop criterion for the penalty 
#' optimization algorithm: the more iterations that are run, the smaller will 
#' the improvement of the corrected Rand index be, and this sets the threshold 
#' when the inner iterations stop. Defaults to 0.01.
#' @param maxIter The maximal number of iterations that are performed in the 
#' penalty optimization.
#' @param log2Off If the automatic detection for high kurtosis, and followingly,
#' the log2 transformation, should be turned off.
#' @param optimARI Above this level of ARI, all solutions are considered equally
#' valid, and the median solution is selected among them.
#' @param center If centering should be performed. Alternatives are 'default', 
#' 'mean', 'peak' and FALSE. 'peak' results in centering around the highest peak
#' in the data, which is useful in most cytometry situations. 'mean' results in
#' mean centering. 'default' gives different results depending on the data: 
#' datasets with 100+ variables are mean centered, and otherwise, peak centering
#' is used. FALSE results in no centering, mainly for testing purposes.
#' @param nCores If multiCore is TRUE, then this sets the number of parallel 
#' processes. The default is currently 87.5 percent with a cap on 10 cores, as 
#' no speed increase is generally seen above 10 cores for normal computers. 
#' @param createOutput For testing purposes. Defaults to TRUE. If FALSE, no 
#' plots are generated.
#' @return A nested list with varying components depending on the setup above:
#' \describe{
#'    \item{clusterVector}{A vector with the same length as number of rows in 
#'    the inDataFrame, where the cluster identity of each observation is 
#'    noted.}
#'    \item{clusterCenters/log2ClusterCenters}{A matrix containing information 
#'    about where the centers are in all the variables that contributed to 
#'    creating the cluster with the given penalty term. Is used by dAllocate. 
#'    If a variable is penalized, its value will appear at the center of the 
#'    data with the centering scheme used in the depeche run, to make dAllocate
#'    function runs possible. If the data was log2-transformed, the cluster 
#'    centers will reflect the log2 transformed positions and the cluter center
#'    matrix wil be named accordingly, not to introduce any unnecessary roundoff
#'    errors.}
#'    \item{sparsityMatrix}{A binary matrix containing information about which 
#'    variables that were sparsed out for each cluster. 1 means that the 
#'    variable was used, 0 that it was discarded.}
#'    \item{penaltyOptList}{A list of two dataframes:
#'    \describe{
#'              \item{penaltyOpt.df}{A one row dataframe with the settings for
#'              the optimal penalty.}
#'              \item{meanOptimDf}{A dataframe with the information about the
#'              results with all tested penalty values.}
#'            }
#'     }
#' } If a dual setup is used, the result will be a nested list, where the first
#' sublist with the information above of the result of the primary clustering
#' and the following list components are the result of all the secondary 
#' clusterings combined.
#' @examples
#' # Load some data
#' data(testData)
#' 
#' # First, just run with the standard settings
#' \dontrun{
#' testDataDepecheResult <- depeche(testData[, 2:15])
#' 
#' # Look at the result
#' str(testDataDepecheResult)
#' 
#' # Now, a dual depeche setup is used
#' testDataDepecheResultDual <- depeche(testData[, 2:15],
#'     dualDepecheSetup = data.frame(rep(1:2, each = 7),
#'     colnames(testData[, 2:15])), penalties = c(64, 128), sampleSize = 500, 
#'     selectionSampleSize = 500, maxIter = 20)
#' 
#' # Look at the result
#' str(testDataDepecheResultDual)
#' }
#' 
#' @export depeche
depeche <- function(inDataFrame, dualDepecheSetup, 
                    penalties = c(2^0, 2^0.5, 2^1, 2^1.5, 2^2, 2^2.5, 2^3, 
                                  2^3.5, 2^4, 2^4.5, 2^5), 
                    sampleSize = "default", selectionSampleSize = "default", 
                    k = 30, minARIImprovement = 0.01, optimARI = 0.95, 
                    maxIter = 100, log2Off = FALSE, center = "default", 
                    nCores="default", createOutput = TRUE) {

    if (is.matrix(inDataFrame)) {
        inDataFrame <- as.data.frame.matrix(inDataFrame)
    }
    
    logCenterSd <- list(FALSE, FALSE, FALSE)
    # Here it is checked if the data has very
    # extreme tails, and if so, the data is
    # log2 transformed
    if (log2Off == FALSE && kurtosis(as.vector(as.matrix(inDataFrame))) > 
        100) {
        kurtosisValue1 <- kurtosis(as.vector(as.matrix(inDataFrame)))
        # Here, the log transformation is
        # performed. In cases where the lowest
        # value is 0, everything is simple. In
        # other cases, a slightly more
        # complicated formula is needed
        if (min(inDataFrame) >= 0) {
            inDataFrame <- log2(inDataFrame + 1)
            logCenterSd[[1]] <- TRUE
        } else {
            # First, the data needs to be reasonably
            # log transformed to not too extreme
            # values, but still without loosing
            # resolution.
            inDataMatrixLog <- log2(apply(inDataFrame, 2, 
                                          function(x) x - min(x)) + 1)
            # Then, the extreme negative values will
            # be replaced by 0, as they give rise to
            # artefacts.
            inDataMatrixLog[which(is.nan(inDataMatrixLog))] <- 0
            inDataFrame <- as.data.frame(inDataMatrixLog)
            logCenterSd[[1]] <- TRUE
        }
        
        kurtosisValue2 <- kurtosis(as.vector(as.matrix(inDataFrame)))
        message("The data was found to be heavily tailed (kurtosis ", 
            kurtosisValue1, "). Therefore, it was log2-transformed, leading to 
            a new kurtosis value of ", kurtosisValue2, ".")
    }
    
    # Centering and overall scaling is
    # performed
    
    if (ncol(inDataFrame) < 100) {
        if (center == "mean") {
            message("Mean centering is applied although the data has less than 
                  100 columns")
            inDataFrameScaleList <- dScale(inDataFrame, scale = FALSE, 
                                           center = "mean", returnCenter = TRUE)
            inDataFramePreScaled <- inDataFrameScaleList[[1]]
            logCenterSd[[2]] <- inDataFrameScaleList[[2]]
        } else if (center == "default" || center == "peak") {
            message("As the dataset has less than 100 columns, peak centering is
                    applied.")
            inDataFrameScaleList <- dScale(inDataFrame, scale = FALSE, 
                                           center = "peak", returnCenter = TRUE)
            inDataFramePreScaled <- inDataFrameScaleList[[1]]
            logCenterSd[[2]] <- inDataFrameScaleList[[2]]
        }
    } else if (center == "peak") {
        message("Peak centering is applied although the data has more than 100 
              columns")
        inDataFrameScaleList <- dScale(inDataFrame, scale = FALSE, 
                                       center = "peak", returnCenter = TRUE)
        inDataFramePreScaled <- inDataFrameScaleList[[1]]
        logCenterSd[[2]] <- inDataFrameScaleList[[2]]
    } else if (center == "default" || center == "mean") {
        message("As the dataset has more than 100 columns, mean centering is 
              applied.")
        inDataFrameScaleList <- dScale(inDataFrame, scale = FALSE, 
                                       center = "mean", returnCenter = TRUE)
        inDataFramePreScaled <- inDataFrameScaleList[[1]]
        logCenterSd[[2]] <- inDataFrameScaleList[[2]]
    } else if (center == FALSE) {
        message("No centering performed")
        inDataFramePreScaled <- inDataFrame
    }
    
    # Here, all the data is divided by the
    # standard deviation of the full dataset
    sdInDataFramePreScaled <- sd(as.matrix(inDataFramePreScaled))
    inDataFrameScaled <- 
        as.data.frame(inDataFramePreScaled/sdInDataFramePreScaled)
    logCenterSd[[3]] <- sdInDataFramePreScaled
    
    # Here, the algorithm forks, depending on if a dual depeche setup has been 
    #chosen or not
    if (missing(dualDepecheSetup)) {
        depecheResult <- depecheCoFunction(
            inDataFrameScaled, plotDir = ".", penalties = penalties, 
            sampleSize = sampleSize, selectionSampleSize = selectionSampleSize, 
            k = k, minARIImprovement = minARIImprovement, 
            optimARI = optimARI, maxIter = maxIter, 
            nCores = nCores, createOutput = createOutput, 
            logCenterSd = logCenterSd)
        return(depecheResult)
    } else {
        inDataColumns <- as.character(dualDepecheSetup[, 2])
        inDataFrameFirst <- 
            inDataFrameScaled[inDataColumns[which(dualDepecheSetup[,1] == 1)]]
        if (is.list(penalties) == FALSE) {
            penaltyList <- list(penalties, penalties)
        }
        dirName1 <- "Level_one_depeche"
        depecheResultFirst <- depecheCoFunction(
            inDataFrameFirst, plotDir = dirName1, penalties = penaltyList[[1]], 
            sampleSize = sampleSize, selectionSampleSize = selectionSampleSize, 
            k = k, minARIImprovement = minARIImprovement, optimARI = optimARI, 
            maxIter = maxIter, nCores=nCores, createOutput = createOutput,
            logCenterSd = logCenterSd)
        
        message("Done with level one clustering where ", 
            length(unique(depecheResultFirst$clusterVector)), 
            " clusters were created. Now initiating level two.")
        
        # After this first step, clustering is
        # performed within each of the clusters
        # produced by the depecheResultFirst
        inDataFrameSecond <- 
            inDataFrameScaled[inDataColumns[which(dualDepecheSetup[,1] == 2)]]
        
        allClusterN <- unique(depecheResultFirst$clusterVector)
        inDataFrameSecondList <- lapply(seq_along(allClusterN), 
                                        function(i) return(
            inDataFrameSecond[which(depecheResultFirst$clusterVector == i), ]
        ))
        
        # Now create the list of cluster numbers
        firstClusterNumberList <- lapply(seq_along(allClusterN), function(i) 
            (100 * i) +1)
        
        # Here, a list of cluster names are
        # created, so that the results are sorted
        # in a correct manner
        directoryNames <- 
            file.path(dirName1, 
                      paste0("Cluster_", seq_along(allClusterN), 
                             "_level_two_depeche"))

        # Here, the secondary clusters are
        # generated for each subframe created by
        # the primary clusters
        depecheResultSecondList <- mapply(depecheCoFunction, 
            inDataFrameSecondList, firstClusterNumberList, 
            directoryNames, MoreArgs = list(penalties = penaltyList[[2]], 
                sampleSize = sampleSize, 
                selectionSampleSize = selectionSampleSize, 
                k = k, minARIImprovement = minARIImprovement, 
                optimARI = optimARI, maxIter = maxIter, nCores=nCores, 
                createOutput = createOutput, logCenterSd = logCenterSd), 
            SIMPLIFY = FALSE)
        
        complexClusterVector <- inDataFrameScaled[,1]
        clusterCentersList <- list()
        colnamesList <- list()
        for (i in seq_along(depecheResultSecondList)) {
            # Here, all the clustering data is
            # recompiled to one long cluster vector
            complexClusterVector[which(depecheResultFirst$clusterVector == 
                i)] <- depecheResultSecondList[[i]][[1]]
            # And the cluster centers are also compiled
            clusterCentersList[[i]] <- depecheResultSecondList[[i]][[2]]
            # And a list of all unique colnames is created
            colnamesList[[i]] <- colnames(clusterCentersList[[i]])
        }
        uniqueColnamesVector <- sort(unique(unlist(colnamesList)))
        
        # Now, if a variable is missing in a
        # certain cluster center matrix, it is
        # added with zeros. Also the variables
        # are sorted.
        for (i in seq_along(clusterCentersList)) {
            if (length(clusterCentersList[[i]]) !=length(
                uniqueColnamesVector)) {
                missingColnames <- 
                    uniqueColnamesVector[!uniqueColnamesVector %in% 
                                             colnames(clusterCentersList[[i]])]
                zeroDataFrame <- 
                    as.data.frame(matrix(0, 
                                         nrow = nrow(clusterCentersList[[i]]), 
                                         ncol = length(missingColnames)))
                colnames(zeroDataFrame) <- missingColnames
                clusterCentersList[[i]] <- cbind(clusterCentersList[[i]], 
                                                 zeroDataFrame)
            }
            
            clusterCentersList[[i]] <- 
                clusterCentersList[[i]][,order(
                    colnames(clusterCentersList[[i]]))]
        }
        
        secondLevelClusterCenters <- do.call("rbind", clusterCentersList)
        
        # And after all these centers have been
        # compiled, the fist set of clusster
        # centers are also included
        firstClusterCenters <- depecheResultFirst$clusterCenters
        firstOnSecondClusterCentersList <- list()
        clusterClusters <- 
            substr(as.character(row.names(secondLevelClusterCenters)), 1, 1)
        for (i in seq_along(clusterClusters)) {
            firstOnSecondClusterCentersList[[i]] <- 
                firstClusterCenters[which(row.names(firstClusterCenters) == 
                clusterClusters[i]), ]
        }
        
        firstOnSecondClusterCenters <- do.call("rbind", 
            firstOnSecondClusterCentersList)
        colnames(firstOnSecondClusterCenters) <- colnames(firstClusterCenters)
        row.names(firstOnSecondClusterCenters) <- 
            row.names(secondLevelClusterCenters)
        
        # And finally, these new columns are
        # added to the complexClusterCenters
        complexClusterCenters <- data.frame(firstOnSecondClusterCenters, 
            secondLevelClusterCenters)
        
        # And now, all the penalty optimization
        # and possible sample size optimizations
        # are saved
        
        penaltyOptListList <- do.call("list", 
            lapply(depecheResultSecondList, "[[", 3))
        
        depecheResult <- list(levelOneCLusterResult = depecheResultFirst, 
            levelTwoClusterVector = complexClusterVector, 
            levelTwoClusterCenters = complexClusterCenters, 
            levelTwoPenaltyOptList = penaltyOptListList)
        
        if (length(sampleSize) > 1) {
            funval <- depecheResultSecondList[[1]][[4]]
            sampleSizeOptList <- do.call("list", 
                vapply(depecheResultSecondList, FUN.VALUE = funval, "[[", 4))
            
            nextClustResultPosition <- length(depecheResult) + 1
            depecheResult[[nextClustResultPosition]] <- 
                as.data.frame.matrix(sampleSizeOptList)
            names(depecheResult)[[length(depecheResult)]] <- 
                "levelTwoSampleSizeOptList"
        }
        
        return(depecheResult)
    }
}
