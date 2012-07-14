#a script for calculating genomic
#estimated breeding values (GEBVs) using rrBLUP

options(echo = FALSE)

library(rrBLUP)
library(plyr)

allArgs <- commandArgs()

inFile <- grep("input_files",
               allArgs,
               ignore.case = TRUE,
               perl = TRUE,
               value = TRUE
               )

print(inFile)
outFile <- grep("output_files",
                allArgs,
                ignore.case = TRUE,
                perl = TRUE,
                value = TRUE
                )

outFiles <- scan(outFile,
                 what="character"
                 )
print(outFile)
print(outFiles)

phenoFile <- grep("pheno",
                  inFile,
                  ignore.case = TRUE,
                  fixed = FALSE,
                  value = TRUE
                  )

genoFile <- grep("geno",
                 inFile,
                 ignore.case=TRUE,
                 fixed = FALSE,
                 value = TRUE
               )

print(phenoFile)

validationFile <- grep("validation",
                       outFiles,
                       ignore.case=TRUE,
                       fixed = FALSE,
                       value=TRUE
                       )
print(validationFile)

blupFile <- grep("kinship",
                 outFiles,
                 ignore.case=TRUE,
                 fixed = FALSE,
                 value=TRUE
                 )

print(blupFile)

markerFile <- grep("marker",
                   outFiles,
                   ignore.case=TRUE,
                   fixed = FALSE,
                   value=TRUE
                   )
print(markerFile)

#test
#validationFile <- c("/data/prod/tmp/solgs/tecle/tempfiles/validation.txt")
#blupFile <- c("/data/prod/tmp/solgs/tecle/tempfiles/top_blup.txt")
#markerFile <- c("/data/prod/tmp/solgs/tecle/tempfiles/marker_effects.txt")
phenoFile <- c("/home/tecle/Desktop/R data/Genomic Selection/barley_jl/cap123Don_sorted.csv")
genoFile <- c("/home/tecle/Desktop/R data/Genomic Selection/barley_jl/cap123geno_sorted.csv")
###

phenoData <- read.table(phenoFile,
                        header = TRUE,
                        row.names = 1,
                        sep = ",",
                        na.strings = c("NA", " ", "--", "-"),
                        dec = "."
                        )

genoData <- read.table(genoFile,
                       header = TRUE,
                       row.names = 1,
                       sep = ",",
                       na.strings = c("NA", " ", "--", "-"),
                       dec = "."
                      )
#add checks for all input data

#convert dataframes into data matrix
phenoDataMatrix <- data.matrix(phenoData)
genoDataMatrix <- data.matrix(genoData)
genoDataMatrix <- round(genoDataMatrix, digits = 1)


#use REML (default) to calculate variance components

#calculate GEBV using marker effects (as random effects)
#genoDataMatrix<-round(genoDataMatrix)
markerGEBV <- mixed.solve(y = phenoDataMatrix,
                          Z = genoDataMatrix
                          )
ordered.markerGEBV2 <- data.matrix(markerGEBV$u)
ordered.markerGEBV2 <- data.matrix(ordered.markerGEBV2 [order (-ordered.markerGEBV2[, 1]), ])
ordered.markerGEBV2 <- round(ordered.markerGEBV2,
                             digits=2
                             )

colnames(ordered.markerGEBV2) <-c("Marker Effects")

#additive relationship model
#calculate the inner products for
#genotypes (realized relationship matrix)
#(change genotype coding to [-1, 0, 1], to use the A.mat )

genocrsprd<-tcrossprod(genoDataMatrix)

#construct an identity matrix for genotypes
identityMatrix <- diag(nrow(phenoDataMatrix))
                     
iGEBV <- mixed.solve(y = phenoDataMatrix,
                     Z = identityMatrix,
                     K = genocrsprd
                     )


#correlation between breeding values based on
#marker effects and relationship matrix
corGEBVs <- cor(genoDataMatrix %*% markerGEBV$u, iGEBV$u)
print(corGEBVs)

iGEBVu <- iGEBV$u
#iGEBVu<-iGEBVu[order(-ans$u), ]
iGEBV <- data.matrix(iGEBVu)

ordered.iGEBV <- as.data.frame(iGEBV [order(-iGEBV[, 1]), ] )

ordered.iGEBV <- round(data.matrix(ordered.iGEBV),
                       digits=2
                       )

colnames(ordered.iGEBV) <- c("blup")

#account for minor allele frequency
#imputation of missing genotypes                     
                     
#cross-validation

reps <- round_any(nrow(phenoDataMatrix), 10, f = ceiling) %/% 10

genotypeGroups <- rep(1:10, reps) [- (nrow(phenoDataMatrix) %% 10)]

set.seed(4567)                                   
genotypeGroups <- genotypeGroups[order (runif(nrow(phenoDataMatrix))) ]                     

##convert genotype values from [1,2] to [0,1]
genoDataMatrix <- genoDataMatrix - 1

validationAll <- c()

for (i in 1:10)
{
  tr <- paste("trPop", i, sep = ".")
  sl <- paste("slPop", i, sep = ".")
 
  trG <- which(genotypeGroups != i)
  slG <- which(genotypeGroups == i)

  assign(tr, trG)
  assign(sl, slG)

  kblup <- paste("rKblup", i, sep = ".")
  
  result <- kinship.BLUP(y = phenoDataMatrix[trG],
                         G.train = genoDataMatrix[trG, ],
                         G.pred = genoDataMatrix[slG, ],
                         mixed.method = "REML",
                         K.method = "RR"
                         )

  assign(kblup, result)
 
#calculate cross-validation accuracy
  accuracy <- try(cor(result$g.pred, phenoDataMatrix[slG]))

  validation <- paste("validation", i, sep = ".")

  cvTest <- paste("Test", i, sep = " ")

  if (class(accuracy) != "try-error")
    {
      accuracy <- round(accuracy, digits = 2)
      accuracy <- data.matrix(accuracy)

      colnames(accuracy) <- c("correlation")
      rownames(accuracy) <- cvTest

      assign(validation, accuracy)

      validationAll <- rbind(validationAll, accuracy)
    }
}

validationAll <- data.matrix(validationAll)
validationAll <- data.matrix(validationAll[order(-validationAll[, 1]), ])
     
if (is.null(validationAll) == FALSE)
  {
    validationMean <- data.matrix(round(colMeans(validationAll),
                                      digits = 2
                                      )
                                )
   
    rownames(validationMean) <- c("Average")
     
    validationAll <- rbind(validationAll, validationMean)
    colnames(validationAll) <- c("Correlation")
  }



if(is.null(validationAll) == FALSE)
    {
      print("val file start")
      write.table(validationAll,
                  file = validationFile,
                  sep = "\t",
                  col.names = NA,
                  quote = FALSE,
                  append = FALSE
                  )
      print("val file end")
    }

if(is.null(ordered.iGEBV) == FALSE)
    {
      print("kinship start")
      write.table(ordered.iGEBV,
                  file = blupFile,
                  sep = "\t",
                  col.names = NA,
                  quote = FALSE,
                  append = FALSE
                  )
      print("kinship end")
    }

if(is.null(ordered.markerGEBV2) == FALSE)
    {
      print("marker file start")
      write.table(ordered.markerGEBV2,
                  file = markerFile,
                  sep = "\t",
                  col.names = NA,
                  quote = FALSE,
                  append = FALSE
                  )
      print("marker file end")
    }

q(save = "no", runLast = FALSE)
