#a script for calculating genomic
#estimated breeding values (GEBVs) using rrBLUP

options(echo = FALSE)

library(rrBLUP)
library(plyr)
#library(sendmailR)
library(mail)

allArgs <- commandArgs()

inFile <- grep("input_files",
               allArgs,
               ignore.case = TRUE,
               perl = TRUE,
               value = TRUE
               )

outFile <- grep("output_files",
                allArgs,
                ignore.case = TRUE,
                perl = TRUE,
                value = TRUE
                )

outFiles <- scan(outFile,
                 what = "character"
                 )

inFiles <- scan(inFile,
                what = "character"
                )

traitsFile <- grep("traits",
                   inFiles,
                   ignore.case = TRUE,
                   fixed = FALSE,
                   value = TRUE
                   )

traitFile <- grep("trait_",
                   inFiles,
                   ignore.case = TRUE,
                   fixed = FALSE,
                   value = TRUE
                   )

## traits <- scan(traitsFile,
##                what = "character",
##                )

trait <- scan(traitFile,
               what = "character",
               )

#traitList<-strsplit(traits, "\t");
#traitsTotal<-length(traitList)
#trait<-traitList[[1]]

validationTrait <- paste("validation", trait, sep = "_")

validationFile  <- grep(validationTrait,
                        outFiles,
                        ignore.case=TRUE,
                        fixed = FALSE,
                        value=TRUE
                        )

kinshipTrait <- paste("kinship", trait, sep = "_")

blupFile <- grep(kinshipTrait,
                 outFiles,
                 ignore.case = TRUE,
                 fixed = FALSE,
                 value = TRUE
                 )

markerTrait <- paste("marker", trait, sep = "_")

markerFile  <- grep(markerTrait,
                   outFiles,
                   ignore.case = TRUE,
                   fixed = FALSE,
                   value = TRUE
                   )

phenoFile <- grep("pheno",
                  inFiles,
                  ignore.case = TRUE,
                  fixed = FALSE,
                  value = TRUE
                  )

phenoData <- read.table(phenoFile,
                        header = TRUE,
                        row.names = 3,
                        sep = "\t",
                        na.strings = c("NA", " ", "--", "-"),
                        dec = "."
                        )

phenoData <- phenoData[order(row.names(phenoData)), ]

dropColumns <- c("uniquename", "stock_id")
phenoData   <- phenoData[,!(names(phenoData) %in% dropColumns)]

phenoTrait <- subset(phenoData,
                     select = c(trait)
                     )

genoFile <- grep("geno",
                 inFiles,
                 ignore.case = TRUE,
                 fixed = FALSE,
                 value = TRUE
                 )

genoFile <- c("/home/tecle/Desktop/R data/Genomic Selection/barley_jl/cap123geno_sorted.csv")

genoData <- read.table(genoFile,
                       header = TRUE,
                       row.names = 1,
                       sep = ",",
                       na.strings = c("NA", " ", "--", "-"),
                       dec = "."
                      )

genoData <- data.matrix(genoData[order(row.names(genoData)), ])

#add checks for all input data
genotypesDiff <- setdiff(row.names(phenoTrait), row.names(genoData))

if (length(genotypesDiff) > 0)
  stop("Genotypes in the phenotype and genotype datasets don't match.")


phenoTrait <- data.matrix(phenoTrait)
genoDataMatrix <- data.matrix(genoData)
genoDataMatrix <- round(genoDataMatrix, digits = 1)


#use REML (default) to calculate variance components

#calculate GEBV using marker effects (as random effects)
#genoDataMatrix<-round(genoDataMatrix)
markerGEBV <- mixed.solve(y = phenoTrait,
                          Z = genoDataMatrix
                          )
ordered.markerGEBV2 <- data.matrix(markerGEBV$u)
ordered.markerGEBV2 <- data.matrix(ordered.markerGEBV2 [order (-ordered.markerGEBV2[, 1]), ])
ordered.markerGEBV2 <- round(ordered.markerGEBV2,
                             digits=2
                             )

colnames(ordered.markerGEBV2) <- c("Marker Effects")

#additive relationship model
#calculate the inner products for
#genotypes (realized relationship matrix)
#(change genotype coding to [-1, 0, 1], to use the A.mat )

genocrsprd <- tcrossprod(genoDataMatrix)

#construct an identity matrix for genotypes
identityMatrix <- diag(nrow(phenoTrait))
                     
iGEBV <- mixed.solve(y = phenoTrait,
                     Z = identityMatrix,
                     K = genocrsprd
                     )


#correlation between breeding values based on
#marker effects and relationship matrix
corGEBVs <- cor(genoDataMatrix %*% markerGEBV$u, iGEBV$u)
#print(corGEBVs)

iGEBVu <- iGEBV$u
#iGEBVu<-iGEBVu[order(-ans$u), ]
iGEBV <- data.matrix(iGEBVu)

ordered.iGEBV <- as.data.frame(iGEBV [order(-iGEBV[, 1]), ] )

ordered.iGEBV <- round(data.matrix(ordered.iGEBV),
                       digits = 2
                       )


combinedGebvsFile <- grep('selected_traits_gebv',
                          outFiles,
                          ignore.case = TRUE,
                          fixed = FALSE,
                          value = TRUE
                          )

fileSize <- file.info(combinedGebvsFile)$size

if (fileSize != 0 )
    {
      combinedGebvs<-read.table(combinedGebvsFile,
                                header = TRUE,
                                row.names = 1,
                                dec = ".",
                                sep = "\t"
                                )

      colnames(ordered.iGEBV) <- c(trait)
      
      traitGEBV <- as.data.frame(ordered.iGEBV)
      allGebvs <- merge(combinedGebvs, traitGEBV,
                        by = 0,
                        all = TRUE                     
                        )
      rownames(allGebvs) <- allGebvs[,1]
      allGebvs[,1] <- NULL
    }
   
colnames(ordered.iGEBV) <- c(trait)
            
#account for minor allele frequency
#imputation of missing genotypes                     
                     
#cross-validation

reps <- round_any(nrow(phenoTrait), 10, f = ceiling) %/% 10

genotypeGroups <- rep(1:10, reps) [- (nrow(phenoTrait) %% 10)]

set.seed(4567)                                   
genotypeGroups <- genotypeGroups[order (runif(nrow(phenoTrait))) ]                     

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
  
  result <- kinship.BLUP(y = phenoTrait[trG],
                         G.train = genoDataMatrix[trG, ],
                         G.pred = genoDataMatrix[slG, ],
                         mixed.method = "REML",
                         K.method = "RR"
                         )

  assign(kblup, result)
 
#calculate cross-validation accuracy
  accuracy <- try(cor(result$g.pred, phenoTrait[slG]))

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
    write.table(validationAll,
                file = validationFile,
                sep = "\t",
                col.names = NA,
                quote = FALSE,
                append = FALSE
                )
  }

if(is.null(ordered.iGEBV) == FALSE)
  {
    write.table(ordered.iGEBV,
                file = blupFile,
                sep = "\t",
                col.names = NA,
                quote = FALSE,
                append = FALSE
                )
  }

if(is.null(ordered.iGEBV) == FALSE)
  {
    write.table(ordered.iGEBV,
                file = blupFile,
                sep = "\t",
                col.names = NA,
                quote = FALSE,
                append = FALSE
                )
  }

if(file.info(combinedGebvsFile)$size == 0)
  {
    write.table(ordered.iGEBV,
                file = combinedGebvsFile,
                sep = "\t",
                col.names = NA,
                quote = FALSE,
                )
  }else
{
  write.table(allGebvs,
              file = combinedGebvsFile,
              sep = "\t",
              quote = FALSE,
              col.names = NA,
              )
}

#should also send notification to analysis owner
to      <- c("<iyt2@cornell.edu>")
subject <- paste(trait, ' GS analysis done', sep = ':')
body    <- c("Dear User,\n\n")
body    <- paste(body, 'The genomic selection analysis for', sep = "")
body    <- paste(body, trait, sep = " ")
body    <- paste(body, "is done.\n\nRegards and Thanks.\nSGN", sep = " ")

#should use SGN's smtp server eventually
sendmail(to,  subject, body, password = "rmail")


q(save = "no", runLast = FALSE)
