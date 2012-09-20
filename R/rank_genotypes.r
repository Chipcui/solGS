#a script for calculating weighted genomic
#estimated breeding values (GEBVs) mean, across
#selected traits, and ranking genotypes accordingly

options(echo = FALSE)

library(stats)

allArgs <- commandArgs()

inFile <- grep("input_rank_genotypes",
               allArgs,
               ignore.case = TRUE,
               perl = TRUE,
               value = TRUE
               )

relWeightsFile <- grep("relative_weights",
                       inFile,
                       ignore.case = TRUE,
                       perl = TRUE,
                       value = TRUE
               )

outFile <- grep("output_rank_genotypes",
                allArgs,
                ignore.case = TRUE,
                perl = TRUE,
                value = TRUE
                )

traitsFiles <- grep("rank_traits_file",
                inFile,
                ignore.case = TRUE,
                perl = TRUE,
                value = TRUE
                )

outFiles <- scan(outFile,
                 what = "character"
                 )

relGebvsFile <- grep("rel_gebvs_",
                     outFiles,
                     ignore.case = TRUE,
                     perl = TRUE,
                     value = TRUE
                     )

inTraitFiles <- scan(traitsFiles,
                what = "character"
                )


traitFilesList <- strsplit(inTraitFiles, "\t");
traitsTotal    <- length(traitList)

if (traitsTotal == 0)
  stop("There are no traits with GEBV data.")
if (length(relWeightsFile) == 0)
  stop("There is no file with relative weights of traits.")


relWeights <- read.table(relWeightsFile,
                            header = TRUE,
                            row.names = 1,
                            sep = "\t",
                            dec = "."
                         )

combinedRelGebvs <- c()

for (i in 1:traitsTotal)
  {
    traitFile <- traitFilesList[[i]]
    traitGEBV <- read.table(traitFile,
                            header = TRUE,
                            row.names = 1,
                            sep = "\t",
                            dec = "."
                            )
    
    trait <- colnames(traitGEBV)
    relWeight <- relWeights[trait, ]
   
    weightedTraitGEBV <- apply(traitGEBV, 1, function(x) x*relWeight)
    
    combinedRelGebvs <- merge(combinedRelGebvs, weightedTraitGEBV,
                              by = 0,
                              all = TRUE                     
                              )

    rownames(combinedRelGebvs) <- combinRelGebvs[, 1]
    combinedRelGebvs[, 1] <- NULL

  }

print(combinedRelGebvs)

combinedRelGebvs$mean <- apply(combinedRelGebvs, 1, mean)
combinedRelGebvs <- combinedRelGebvs[ with(combinedRelGebvs, order(-combinedRelGebvs$mean)), ]
combinedRelGebvs <- round(combinedRelGebvs,
                          digits = 2
                          )

if (length(relGebvsFile) != 0)
  {
    if(is.null(combinedRelGebvs) == FALSE)
      {
        write.table(combinedRelGebvs,
                    file = relGebvsFile,
                    sep = "\t",
                    col.names = NA,
                    quote = FALSE,
                    append = FALSE
                    )
      }
  }

q(save = "no", runLast = FALSE)
