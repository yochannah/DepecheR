# dAllocate

# IDEA: TAKE A DATASET THAT WE ALLOCATE CORRECTLY TO 99%, THEN CHECK THAT THIS 
#HAPPENS WITH THE RAND INDEX!!!
context("dAllocate")
cols <- 150
x <- DepecheR:::generateBimodalData(observations = 20, dataCols = cols)
centers <- rbind(runif(cols) + 50, runif(cols) - 50)
out <- dAllocate(x$samples, centers)
test_that("dAllocate expected output", {
    expect_true(all(out == x$ids))
})

# Here, we are comparing if allocating the same data to the cluster centers 
#genreated with depeche gives an ARI
# of 1, which it should
colnames(x[[1]]) <- paste0("V", seq_len(ncol(x[[1]])))
depRes <- depeche(x[[1]], center = FALSE, nCores=2, createOutput=FALSE)
allocRes <- dAllocate(x[[1]], depRes[[2]])
test_that("dAllocate expected output", {
    expect_true(DepecheR:::rand_index(depRes$clusterVector, allocRes, 
                                      k = 100) == 1)
})
