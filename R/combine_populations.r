#formats and combines phenotype (of a single trait)
#and genotype datasets of multiple
#training populations

options(echo = FALSE)

library(stats)
library(stringr)
library(imputation)
library(plyr)

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
print(outFiles)

inFiles <- scan(inFile,
                what = "character"
                )
print(inFiles)

traitFile <- grep("trait_",
                  inFiles,
                  ignore.case = TRUE,
                  fixed = FALSE,
                  value = TRUE
                  )

trait <- scan(traitFile,
              what = "character",
              )
print(trait)

traitInfo<-strsplit(trait, "\t");
traitId<-traitInfo[[1]]
traitName<-traitInfo[[2]]
print(traitId)
print(traitName)

#extract trait phenotype data from all populations
#and combine them into one dataset

allPhenoFiles <- grep("phenotype_data",
                  inFiles,
                  ignore.case = TRUE,
                  fixed = FALSE,
                  value = TRUE
                  )
print(allPhenoFiles)

allGenoFiles <- grep("genotype_data",
                  inFiles,
                  ignore.case = TRUE,
                  fixed = FALSE,
                  value = TRUE
                  )


print(allGenoFiles)

popsPhenoSize     <- length(allPhenoFiles)
popsGenoSize      <- length(allGenoFiles)
popIds            <- c()
combinedPhenoPops <- c()

for (i in 1:popsPhenoSize)
  {
    popId <- str_extract(allPhenoFiles[[i]], "\\d+")
    popIds <- append(popIds, popId)

    print(popId)
    phenoData <- read.table(allPhenoFiles[[i]],
                            header = TRUE,
                            row.names = 1,
                            sep = "\t",
                            na.strings = c("NA", " ", "--", "-"),
                            dec = "."
                           )


    phenoTrait <- subset(phenoData,
                         select = c("object_name", "stock_id", traitName)
                         )
  
    if (sum(is.na(phenoTrait)) > 0)
      {
        print("sum of pheno missing values")
        print(sum(is.na(phenoTrait)))

        #fill in for missing data with mean value
        phenoTrait[, traitName]  <- replace (phenoTrait[, traitName],
                                             is.na(phenoTrait[, traitName]),
                                             mean(phenoTrait[, traitName], na.rm =TRUE)
                                            )
         
       #calculate mean of reps/plots of the same accession and
       #create new df with the accession means
        phenoTrait$stock_id <- NULL
        phenoTrait   <- phenoTrait[order(row.names(phenoTrait)), ]
   
        print('phenotyped lines before averaging')
        print(length(row.names(phenoTrait)))
        
        phenoTrait<-ddply(phenoTrait, "object_name", colwise(mean))
        
        print('phenotyped lines after averaging')
        print(length(row.names(phenoTrait)))
   
        row.names(phenoTrait) <- phenoTrait[, 1]
        phenoTrait[, 1] <- NULL


      } else {
      print ('No missing data')
      phenoTrait$stock_id <- NULL
      phenoTrait   <- phenoTrait[order(row.names(phenoTrait)), ]
   
      print('phenotyped lines before averaging')
      print(length(row.names(phenoTrait)))
      
      phenoTrait<-ddply(phenoTrait, "object_name", colwise(mean))
      
      print('phenotyped lines after averaging')
      print(length(row.names(phenoTrait)))

      row.names(phenoTrait) <- phenoTrait[, 1]
      phenoTrait[, 1] <- NULL

    }

    newTraitName = paste(traitName, popId, sep = "_")
    colnames(phenoTrait)[1] <- newTraitName

    if (i == 1 )
      {
        print('no need to combine, yet')       
        combinedPhenoPops <- phenoTrait
        
      } else {
      print('combining...') 
      combinedPhenoPops <- merge(combinedPhenoPops, phenoTrait,
                            by = 0,
                            all=TRUE,
                            )

      rownames(combinedPhenoPops) <- combinedPhenoPops[, 1]
      combinedPhenoPops$Row.names <- NULL
      
    }   
}

markersList <- c()

for (i in 1:popsGenoSize)
  {
    popId <- str_extract(allGenoFiles[[i]], "\\d+")
    popIds <- append(popIds, popId)

    print(popId)
    genoData <- read.table(allGenoFiles[[i]],
                            header = TRUE,
                            row.names = 1,
                            sep = "\t",
                            na.strings = c("NA", " ", "--", "-"),
                            dec = "."
                           )
    print ('geno data')
    print (genoData[1:10, 1:10])
    popMarkers <- colnames(genoData)
    print(length(popMarkers))
    print(popMarkers)
  
    if (sum(is.na(genoData)) > 0)
      {
        print("sum of geno missing values")
        print(sum(is.na(genoData)))

        genoDataMatrix <-kNNImpute(genoDataMatrix, 10)
        genoDataMatrix <-as.data.frame(genoDataMatrix)

        #extract columns with imputed values
        genoDataMatrix <- subset(genoDataMatrix,
                                select = grep("^x", names(genoDataMatrix))
                                )

        #remove prefix 'x.' from imputed columns
        names(genoDataMatrix) <- sub("x.", "", names(genoDataMatrix))

        genoDataMatrix <- round(genoDataMatrix, digits = 0)
        genoDataMatrix <- data.matrix(genoDataMatrix)
      }
 
  }

#print(combinedPhenoPops)


q(save = "no", runLast = FALSE)
