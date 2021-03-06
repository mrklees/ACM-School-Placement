rm(list=ls())

# Load packages with no printed warnings or errors
suppressWarnings(suppressMessages(library("data.table")))
suppressWarnings(suppressMessages(library("dplyr")))
suppressWarnings(suppressMessages(library("readxl")))
suppressWarnings(suppressMessages(library("tidyr")))

# Load Functions
source("cleaning.R")
source("placement_algorithm.R")

# Load Parameters
dataset <- read.csv('media/documents/inputs/params.csv', stringsAsFactors=FALSE)
dataset$acm_input_path <- 'media/documents/inputs/ACM_Placement_Survey_Data.csv'
dataset$sch_input_path <- 'media/documents/inputs/ACM_Placement_School_Data.xlsx'
dataset$consider_HS_elig <- as.logical(dataset$consider_HS_elig)
dataset$prevent_roommates <- as.logical(dataset$prevent_roommates)
dataset$calc_commutes <- as.logical(dataset$calc_commutes)

score_factors <- list(
  commute_factor=dataset$commute_factor,
  Edscore_factor=dataset$Edscore_factor,
  Math_factor=0, # remove altogether?
  age_factor=0,
  ethnicity_factor=dataset$ethnicity_factor,
  Tutoring_factor=0,
  Spanish_factor=dataset$Spanish_factor,
  gender_factor=dataset$gender_factor,
  preserve_ij_factor=0
)

output_path <- 'media/documents/outputs/'

# Load and Clean Inputs
acm_df <- read.csv(dataset$acm_input_path, check.names=FALSE, stringsAsFactors=FALSE)
school_df <- read_excel(dataset$sch_input_path)

if(score_factors$commute_factor > 0){
  acm_commutes <- read.csv(paste0(output_path, 'Output_Commute_Reference.csv'), check.names=FALSE)
  acm_commutes$Time.Mins <- as.numeric(as.character(acm_commutes$Time.Mins))
  acm_commutes$id_dest <- paste(acm_commutes$Full.Name, acm_commutes$School, sep = "_")
} else {
  acm_commutes <- data.frame(id_dest = NA, 
                             Full.Name	= NA,
                             School	= NA,
                             Home.Address	= NA,
                             School.Address	= NA,
                             Travel.Mode	= NA,
                             Time.Mins	= NA,
                             Distance.Miles = NA,
                             Status	= NA,
                             Rank = NA
                             )
}
dt_commutes <- data.table(acm_commutes)

result <- clean_inputs(acm_df, school_df)
acm_df <- result[[1]]
school_df <- result[[2]]

# Replace all empty strings with NA
acm_df[,][acm_df[,] == ""] <- NA

acm_enc <- encode_acm_df(acm_df)

school_targets <- school_config(school_df, acm_enc)

team_placements_df <- initial_placement(acm_enc, school_targets)

# For IJ Placement, read in school placement, remove any manual.placements
#prior_placements <- read.csv("Z:\\ChiPrivate\\Chicago Data and Evaluation\\SY19\\School Team Placement\\2018-08-05 Placements and Notes\\SY19_08-05_Output_Placements.csv", check.names=FALSE, stringsAsFactors=FALSE)
#prior_placements$School.Placement <- prior_placements$School
#
#team_placements_df <- merge(team_placements_df, prior_placements[c("Full.Name", "School.Placement")], by="Full.Name", all.x=TRUE)
#team_placements_df$Manual.Placement <- NA
#team_placements_df <- merge(team_placements_df, school_df[c("School", "Team Leader")], by.x = "School.Placement", by.y = "School", all.x = TRUE)
#team_placements_df$Prior.Rship.Names <- apply(team_placements_df[, c("Prior.Rship.Names", "Team Leader")], 1, function(x) toString(na.omit(x)))
#team_placements_df <- team_placements_df[!names(team_placements_df) %in% "Team Leader"]
#
#score_factors$commute_factor <- 0
#score_factors$ethnicity_factor <- 1
#score_factors$gender_factor <- 1
#score_factors$Edscore_factor <- 1
#score_factors$Spanish_factor <- 0
#score_factors$preserve_ij_factor <- 1
#dataset$number_iterations <- 5000

# load from output
#prior_placements <- read.csv("Z:\\ChiPrivate\\Chicago Data and Evaluation\\SY19\\School Team Placement\\2018-08-05 Placements and Notes\\ACM_Placement_Result_8k_iter_Spanish_3\\Output_Placements.csv", check.names=FALSE, stringsAsFactors=FALSE)
#team_placements_df <- merge(team_placements_df[!names(team_placements_df) %in% "placement"], prior_placements[c("acm_id", "placement")], by="acm_id", all.x=TRUE)

elig_plc_schwise_df <- elig_plcmnts_schwise(team_placements_df, school_df, dataset$consider_HS_elig)
elig_plc_acmwise_df <- elig_plcmnts_acmwise(team_placements_df, dataset$prevent_roommates)

team_placements_df <- initial_valid_placement(team_placements_df, school_df, elig_plc_schwise_df, elig_plc_acmwise_df)

output <- run_intermediate_annealing_process(starting_placements = team_placements_df, school_df = school_targets, 
                                             best_placements = team_placements_df, number_of_iterations = dataset$number_iterations, 
                                             center_scale=runif(1, 1e-3, 0.25), width_scale=runif(1, 1e-3, 0.25))

best_placements <- output$best_placements

# Merge in School Name
best_placements <- merge(best_placements, school_df[, c("School", "sch_id")], by.x = "placement", by.y = "sch_id", all.x = TRUE)
# Merge in Survey
best_placements <- merge(best_placements, acm_df, by = "acm_id", all.x = TRUE)

# Merge in commute info
if(score_factors$commute_factor > 0){
  best_placements <- within(best_placements, id_dest <- paste(Full.Name, School, sep = "_"))
  commutes <- dt_commutes[, ]
  best_placements <- merge(best_placements, commutes[id_dest %in% best_placements$id_dest, c("Full.Name", "Time.Mins", "Rank")], by = "Full.Name", all.x = TRUE)
  names(best_placements)[names(best_placements) == 'Time.Mins'] <- 'Commute.Time.Mins'
  names(best_placements)[names(best_placements) == 'Rank'] <- 'Commute.Rank'
} else {
  best_placements$Commute.Time.Mins <- NA
  best_placements$Commute.Rank <- NA
}

# best_placements$acm_id[best_placements$acm_id > nrow(acm_enc)] <- 800:(800 + sum(school_df$size) - nrow(acm_enc) - 1)

# Hide "blown up" scores for a smoother, more interpretable graph
if(output$best_score < 1000000){
  trace <- output$trace[output$trace$score < 1000000 & output$trace$score > 0,]
} else {
  trace <- output$trace[output$trace$score > 0,]
}

write.table(best_placements, file = paste0(output_path, "Output_Placements.csv"), sep=",", row.names=FALSE, na = "")
write.table(trace, file = paste0(output_path, "Output_Trace.csv"), sep=",", row.names=FALSE, na = "")

# pass new placements back in
#team_placements_df <- merge(best_placements[c("acm_id", "placement")], team_placements_df[!names(team_placements_df) %in% "placement"], by="acm_id", all.x=TRUE)
#View(trace)
#plot(trace[,c('iter', 'score')])
#mean(best_placements$Commute.Time[best_placements$Commute.Time != 999], na.rm = TRUE)
#mean(best_placements$Commute.Rank, na.rm = TRUE)