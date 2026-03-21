##supplement - running files.
library(mizer)
library(dplyr)
library(tidyr)
library(Rcpp)
library(patchwork)
library(assertthat)
library(tidyverse)
setClass( 
  "MizerSim",
  slots = c(
    params = "MizerParams",
    n = "array",
    effort = "array",
    n_pp = "array",
    n_other = "array",
    waa = "array"
  )
)

MizerSim <- function(params, t_dimnames = NA, t_max = 100, t_save = 1, 
                     #####################
                     agetesters = 20, 
                     #####################
                     dt = 0.1) {
  # If the dimnames for the time dimension not passed in, calculate them
  # from t_max and t_save
  if (any(is.na(t_dimnames))) {
    t_dimnames <- seq(from = 0, to = t_max, by = t_save)
  }
  if (!is.numeric(t_dimnames)) {
    stop("The t_dimnames argument must be numeric.")
  }
  if (is.unsorted(t_dimnames)) {
    stop("The t_dimnames argument should be increasing.")
  }
  
  
  no_sp <- nrow(params@species_params)
  species_names <- dimnames(params@psi)$sp
  no_w <- length(params@w)
  w_names <- dimnames(params@psi)$w
  no_t <- length(t_dimnames)
  
  array_n <- array(NA, dim = c(no_t, no_sp, no_w), 
                   dimnames = list(time = t_dimnames, 
                                   sp = species_names, w = w_names))
  
  no_gears <- dim(params@selectivity)[1]
  gear_names <- dimnames(params@selectivity)$gear
  array_effort <- array(NA, dim = c(no_t, no_gears), 
                        dimnames = list(time = t_dimnames, 
                                        gear = gear_names))
  
  no_w_full <- length(params@w_full)
  w_full_names <- names(params@rr_pp)
  array_n_pp <- array(NA, dim = c(no_t, no_w_full), 
                      dimnames = list(time = t_dimnames, 
                                      w = w_full_names))
  
  component_names <- names(params@other_dynamics)
  no_components <- length(component_names)
  list_n_other <- rep(list(NA), no_t * no_components)
  dim(list_n_other) <- c(no_t, no_components)
  dimnames(list_n_other) <- list(time = t_dimnames,
                                 component = component_names)
  
  
  #####################
  waa <- array(NA, dim = c(no_t, no_sp, agetesters),
               dimnames = list (time = t_dimnames,
                                sp=species_names,
                                agetesters=seq(agetesters)
               ))
  #####################
  
  sim <- new("MizerSim",
             params = params,
             n = array_n,
             n_pp = array_n_pp,
             n_other = list_n_other,
             effort = array_effort,
             #####################
             waa = waa
             #####################
  )
  return(sim)
}

#have to run it all at once then it works - for some reason
(project <- function(object, effort,
                    t_max = 100, dt = 0.1, t_save = 0.1, t_start = 0,
                    initial_n, initial_n_pp,
                    append = TRUE,
                    progress_bar = TRUE,
                    #####################
                    waa_initial,
                    nages=20,
                    #####################
                    ...) {
  
  # Set and check initial values ----
  assert_that(t_max > 0)
  if (is(object, "MizerSim")) {
    validObject(object)
    params <- setInitialValues(object@params, object)
    waa_initial <- object@waa[idxFinalT(object),,]
    t_start <- getTimes(object)[idxFinalT(object)]
  } else if (is(object, "MizerParams")) {
    params <- validParams(object)
    if (!missing(initial_n)) params@initial_n[] <- initial_n
    if (!missing(initial_n_pp)) params@initial_n_pp[] <- initial_n_pp
  } else {
    stop("The `object` argument must be either a MizerParams or a MizerSim object.")
  }
  initial_n <- params@initial_n
  initial_n_pp <- params@initial_n_pp
  initial_n_other <- params@initial_n_other
  
  no_sp <- length(params@w_min_idx)
  assert_that(is.array(initial_n),
              is.numeric(initial_n),
              are_equal(dim(initial_n), c(no_sp, length(params@w))))
  assert_that(is.numeric(initial_n_pp),
              length(initial_n_pp) == length(params@w_full))
  
  assert_that(is.null(initial_n_other) || is.list(initial_n_other))
  other_names <- names(params@other_dynamics)
  if (length(other_names) > 0) {
    if (is.null(names(initial_n_other))) {
      stop("The initial_n_other needs to be a named list")
    }
    if (!setequal(names(initial_n_other), other_names)) {
      stop("The names of the entries in initial_n_other do not match ",
           "the names of the other components of the model.")
    }
  }
  
  # Set effort array ----
  if (missing(effort)) effort <- params@initial_effort
  if (is.null(dim(effort))) { # effort is a vector or scalar
    # Set up the effort array transposed so we can use the recycling rules
    # no point running a simulation with no saved results
    if (t_max < t_save) {
      t_save <- t_max
    }
    times <- seq(t_start, t_start + t_max, by = t_save)
    effort <- validEffortVector(effort, params)
    effort <- t(array(effort, 
                      dim = c(length(effort), length(times)), 
                      dimnames = list(gear = names(effort), 
                                      time = times)))
  } else {
    effort <- validEffortArray(effort, params)
  }
  
  times <- as.numeric(dimnames(effort)[[1]])
  
  #####################
  if(missing(waa_initial)){
    ##AT THE BOTTOM OF THIS FILE IS THIS FUNCTION!
    pre_Waa_initial <- getintegergrowthcurves(object, max_age = nages)
    
    pre_Waa_initial <- pre_Waa_initial[,-1]
    
    waa_initial <- as.matrix(pre_Waa_initial)
  }
  
  waa_save <- array(0,dim = c(length(times),nrow(waa_initial),ncol(waa_initial)))
  #####################
  
  # Make the MizerSim object with the right size ----
  # We only save every t_save years
  sim <- MizerSim(params, t_dimnames = times)
  # Set initial population and effort
  sim@n[1, , ] <- initial_n 
  sim@n_pp[1, ] <- initial_n_pp
  sim@n_other[1, ] <- initial_n_other
  sim@effort <- effort
  
  #####################
  sim@waa[1,,] <- waa_initial
  waa <- waa_initial
  #####################
  
  ## Initialise ----
  # get functions
  resource_dynamics_fn <- get(params@resource_dynamics)
  other_dynamics_fns <- lapply(params@other_dynamics, get)
  rates_fns <- lapply(params@rates_funcs, get)
  
  
  # Set up progress bar
  if (is(progress_bar, "Progress")) {
    # We have been passed a shiny progress object
    progress_bar$set(message = "Running simulation", value = 0)
    proginc <- 1 / length(times)
  } else if (progress_bar == TRUE) {
    pb <- progress::progress_bar$new(
      format = "[:bar] :percent ETA: :eta",
      total = length(times), width = 60)
    pb$tick(0)
  }
  
  n_list <- list(n = initial_n, n_pp = initial_n_pp,
                 n_other = unserialize(serialize(initial_n_other, NULL)))
  t <- times[[1]]
  
  ## Loop over time ----
  for (i in 2:length(times)) {
    
    #print(waa)
    
    ########
    #add new tester if necessary
    #when t = integer, release new tester.
    #needs to be weirdly coded like this because there are little variations
    if (abs(t - round(t)) < .Machine$double.eps^0.5) {
      waa <- cbind(params@species_params$w_min,waa[,-(ncol(waa))])
    }
    ########
    
    # number of time steps between saved times
    steps <- round((times[[i]] - t) / dt)
    # advance to next saved time
    n_list <- project_simple(
      params, n = n_list$n, n_pp = n_list$n_pp, n_other = n_list$n_other,
      t = t, dt = dt, steps = steps, 
      effort = effort[i - 1, ],
      resource_dynamics_fn = resource_dynamics_fn,
      other_dynamics_fns = other_dynamics_fns,
      rates_fns = rates_fns, 
      #####################
      waa = waa, 
      #####################
      ...)
    
    
    # Calculate start time for next iteration
    # The reason we don't simply use the next entry in `times` is that
    # those entries may not be separated by exact multiples of dt.
    t <- t + steps * dt
    
    
    # Advance progress bar
    if (is(progress_bar, "Progress")) {
      progress_bar$inc(amount = proginc)
    } else if (progress_bar == TRUE) {
      pb$tick()
    }
    
    # Store result
    sim@n[i, , ] <- n_list$n
    sim@n_pp[i, ] <- n_list$n_pp
    sim@n_other[i, ] <- unserialize(serialize(n_list$n_other, NULL))
    
    #####################
    sim@waa[i,,] <- n_list$waa
    #change the waa to new waa
    waa <- n_list$waa
    #####################
    
  }
  
  
  
  # append to previous simulation ----
  if (is(object, "MizerSim") && append) {
    no_t_old <- dim(object@n)[1]
    no_t <- length(times)
    new_t_dimnames <- c(as.numeric(dimnames(object@n)[[1]]),
                        times[2:no_t])
    new_sim <- MizerSim(params, t_dimnames = new_t_dimnames)
    old_indices <- 1:no_t_old
    new_indices <- seq(from = no_t_old + 1, length.out = no_t - 1)
    new_sim@n[old_indices, , ]  <- object@n
    new_sim@n[new_indices, , ]  <- sim@n[2:no_t, , ]
    new_sim@n_pp[old_indices, ] <- object@n_pp
    new_sim@n_pp[new_indices, ] <- sim@n_pp[2:no_t, ]
    new_sim@n_other[old_indices, ]  <- object@n_other
    new_sim@n_other[new_indices, ]  <- sim@n_other[2:no_t, ]
    new_sim@effort[old_indices, ] <- object@effort
    new_sim@effort[new_indices, ] <- sim@effort[2:no_t, ]
    new_sim@waa[old_indices,,] <- object@waa
    new_sim@waa[new_indices,,] <- sim@waa[2:no_t,,]
    
    return(new_sim)
  }
  return(sim)
})

project_simple <- 
  function(params, 
           n = params@initial_n,
           n_pp = params@initial_n_pp,
           n_other = params@initial_n_other,
           effort = params@initial_effort,
           t = 0, dt = 0.1, steps,
           resource_dynamics_fn = get(params@resource_dynamics),
           other_dynamics_fns = lapply(params@other_dynamics, get),
           rates_fns = lapply(params@rates_funcs, get),
           #####################
           waa
           #####################
           , ...) {    
    # Handy things ----
    no_sp <- nrow(params@species_params) # number of species
    no_w <- length(params@w) # number of fish size bins
    idx <- 2:no_w
    # Hacky shortcut to access the correct element of a 2D array using 1D 
    # notation
    # This references the egg size bracket for all species, so for example
    # n[w_min_idx_array_ref] = n[,w_min_idx]
    w_min_idx_array_ref <- (params@w_min_idx - 1) * no_sp + (1:no_sp)
    # Matrices for solver
    a <- matrix(0, nrow = no_sp, ncol = no_w)
    b <- matrix(0, nrow = no_sp, ncol = no_w)
    S <- matrix(0, nrow = no_sp, ncol = no_w)
    
    # Loop over time steps ----
    for (i_time in 1:steps) {
      r <- rates_fns$Rates(
        params, n = n, n_pp = n_pp, n_other = n_other,
        t = t, effort = effort, rates_fns = rates_fns, ...)
      
      # * Update other components ----
      n_other_new <- list()  # So that the resource dynamics can still 
      # use the current value
      for (component in names(params@other_dynamics)) {
        n_other_new[[component]] <-
          other_dynamics_fns[[component]](
            params,
            n = n,
            n_pp = n_pp,
            n_other = n_other,
            rates = r,
            t = t,
            dt = dt,
            component = component,
            ...
          )
      }
      
      # * Update resource ----
      n_pp <- resource_dynamics_fn(params, n = n, n_pp = n_pp,
                                   n_other = n_other, rates = r,
                                   t = t, dt = dt,
                                   resource_rate = params@rr_pp,
                                   resource_capacity = params@cc_pp, ...)
      
      # * Update species ----
      # a_{ij} = - g_i(w_{j-1}) / dw_j dt
      a[, idx] <- sweep(-r$e_growth[, idx - 1, drop = FALSE] * dt, 2,
                        params@dw[idx], "/")
      # b_{ij} = 1 + g_i(w_j) / dw_j dt + \mu_i(w_j) dt
      b[] <- 1 + sweep(r$e_growth * dt, 2, params@dw, "/") + r$mort * dt
      # S_{ij} <- N_i(w_j)
      S[, idx] <- n[, idx, drop = FALSE]
      # Update first size group of n
      n[w_min_idx_array_ref] <-
        (n[w_min_idx_array_ref] + r$rdd * dt / 
           params@dw[params@w_min_idx]) /
        b[w_min_idx_array_ref]
      
      
      
      #####################
      # waa <- t(sapply(1:no_sp,update_waa,grow=r$e_growth,waa=waa,dt=dt,params=params))
      waa <- new_waa(waa, r$e_growth, dt, params@w)
      #####################
      
      # Update n
      # for (i in 1:no_sp) # number of species assumed small, so no need to 
      #                      vectorize this loop over species
      #     for (j in (params@w_min_idx[i]+1):no_w)
      #         n[i,j] <- (S[i,j] - A[i,j]*n[i,j-1]) / B[i,j]
      # This is implemented via Rcpp
      n <- mizer:::inner_project_loop(no_sp = no_sp, no_w = no_w, n = n,
                                      A = a, B = b, S = S,
                                      w_min_idx = params@w_min_idx)
      
      # * Update time ----
      t <- t + dt
    }
    
    return(list(n = n, n_pp = n_pp, n_other = n_other_new, rates = r, 
                #####################
                waa = waa
                #####################
    ))
  }

cppFunction(code='
#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export]]
NumericMatrix new_waa(NumericMatrix waa, NumericMatrix allgrow, double dt, 
                      NumericVector we, Nullable<IntegerVector> spec = R_NilValue) {
  // Make a copy of waa
  NumericMatrix newwaa = clone(waa);

  int n_sp = waa.nrow();
  int n_w  = waa.ncol();
  int n_w_allgrow = allgrow.ncol();
  
  // Check the last column of allgrow: if any value > 1e-10, then set the entire last column to 0 and warn.
  bool warn_flag = false;
  for (int j = 0; j < allgrow.nrow(); j++){
    if (allgrow(j, n_w_allgrow - 1) > 1e-10) {
      warn_flag = true;
      break;
    }
  }
  if (warn_flag) {
    for (int j = 0; j < allgrow.nrow(); j++){
      allgrow(j, n_w_allgrow - 1) = 0;
    }
    Rcpp::warning("growth in last class not zero. I have set it to zero. I recommend that you change the final column in psi to 1 else I\'ll keep telling you off.");
  }
  
  // Determine species to iterate
  std::vector<int> species_to_iterate;
  if (spec.isNotNull()){
    IntegerVector sp = as<IntegerVector>(spec);
    for (int i = 0; i < sp.size(); i++){
      // Assuming provided indices are 1-based; convert to 0-based:
      species_to_iterate.push_back(sp[i] - 1);
    }
  } else {
    for (int j = 0; j < n_sp; j++){
      species_to_iterate.push_back(j);
    }
  }
  
  // Loop over species and weight classes
  for (int j : species_to_iterate) {
    for (int i = 0; i < n_w; i++){
      double cur_waa = waa(j, i);
      NumericVector grow = allgrow(j, _);
      double time_left = dt;
      
      while(time_left > 0){
        int cur_idx = 0;
        for (int k = 0; k < we.size(); k++){
          if (cur_waa >= we[k]) {
            cur_idx = k;
          }
        }
        double g = grow[cur_idx];
        double time_to_end;
        if (g < 1e-10) {
          time_to_end = time_left;
        } else {
          if (cur_idx + 1 < we.size()){
            double togro = we[cur_idx + 1];
            time_to_end = (togro - cur_waa) / g;
          } else {
            time_to_end = time_left;
          }
        }
        
        if(time_to_end < time_left){
          time_left = time_left - time_to_end;
          if (cur_idx + 1 < we.size() && g >= 1e-10) {
            cur_waa = we[cur_idx + 1];
          }
        } else {
          cur_waa = cur_waa + g * time_left;
          time_left = 0;
        }
      }
      
      newwaa(j, i) = cur_waa;
    }
  }
  
  return newwaa;
}
')

#loading up mizerparams - so that it is the same regardless of no_w
NS_species <- NS_species_params_gears
NS_species$b <- c(3.014,3.32,2.941,3.429,2.986,3.080,3.019,3.198,3.010,3.160,3.173,3.075)
NS_species$alpha <- 0.6
NS_species$f0 <- 0.6
NS_species$a <- c(0.007,0.001,0.009,0.002,0.010,0.006,0.008,0.004,0.007,0.005,0.005,0.007)
params <- newMultispeciesParams(NS_species, interaction = NS_params@interaction,kappa=1e11)
gear_params(params) <- data.frame(
  species = c("Sprat", "Sandeel", "N.pout", "Herring", "Dab", "Whiting", 
              "Sole", "Gurnard", "Plaice", "Haddock", "Cod", "Saithe"),
  gear = c("Sprat", "Sandeel", "N.pout", "Herring", "Dab", "Whiting", 
           "Sole", "Gurnard", "Plaice", "Haddock", "Cod", "Saithe"),
  sel_func = rep("sigmoid_length", 12),
  catchability = rep(1, 12),
  l25=c(7.65,11.52,19.810,9.83,8.690,10.130,19.81,16.4,11.52,19.09,13.2,35.32),
  l50 = c(8.14,17.04,29.02,11.82,12.40,20.79,29.02,25.8,17.04,24.34,22.87,43.55),
  stringsAsFactors = FALSE
)

library(readr)
historicfishingM <- read_csv("historicfishingM.csv")%>%
  rename(N.pout=N.Pout)

#sorting fishing effort
newdt <- 0.1
years <- historicfishingM$Year
desired_order <- dimnames(params@catchability)[[1]]
fishing_effort_dt <- historicfishingM[rep(1:nrow(historicfishingM), each = 1/newdt), ]
fishing_effort_dt$Year <- rep(seq(min(historicfishingM$Year), 
                                  max(historicfishingM$Year) + 1 - newdt, 
                                  by = newdt), length.out = nrow(fishing_effort_dt))
fishing_effort_dt <- rbind(fishing_effort_dt, within(fishing_effort_dt[nrow(fishing_effort_dt), ], Year <- Year + newdt))
fishing_array <- array(NA, dim = c(length(fishing_effort_dt$Year), length(desired_order)),
                       dimnames = list(Year = fishing_effort_dt$Year, Species = desired_order))
fishing_array[,] <- as.matrix(fishing_effort_dt[, desired_order])

params@initial_effort <- fishing_array[1,]

tosteady <- project(params, effort = fishing_array[1,],t_max =100, initial_n = params@initial_n)
projection <- project(params, effort = fishing_array,  initial_n = (tosteady@n)[(dim(tosteady@n)[1]),,],
                      initial_n_pp = (tosteady@n_pp)[(dim(tosteady@n)[1]),],
                      waa_initial = tosteady@waa[1001,,], dt = newdt) 

load("C:/Users/LB19/OneDrive - CEFAS/Work/mizerAge/waa.Rdata")

#this plots fig2.2 - included maybe?

growth <- tosteady@waa[1001,6,]
growth <- as.data.frame(growth)%>%rownames_to_column(var="age")

mizergrowth <- as.data.frame(getGrowthCurves(tosteady, species = "Whiting")) %>%
  rownames_to_column("Species") %>%
  pivot_longer(
    cols = -Species,
    names_to = "w",
    values_to = "Value"
  ) %>%
  mutate(w = as.numeric(w))


ggplot(data=growth)+
  geom_line(aes(x=as.numeric(age), y= growth), size = 1, color="grey")+
  geom_line(data=mizergrowth, aes(x=as.numeric(w), y=Value))+
  theme_minimal()+
  labs(x="Age", y="w (g)")

#this plots fig2.3
par(mfrow=c(3,2))
par(oma=c(2,2,0,1))
par(mar=c(2,2,2,3))
for(i in 2:7){
  plot(1974:2022,waa$WHG[,i], type="l",main=paste("Age",i-1),xlab="",ylab="")
  par(new = TRUE)
  proj_years <- as.numeric(floor(as.numeric(names(projection@waa[-1,6,i-1]))-0.1))
  tmp_aggregated <- tapply(projection@waa[-1,6,i-1], proj_years, mean, na.rm=TRUE)
  tmp_aggregated <- c(rep(NA,10),tmp_aggregated,rep(NA,3))
  plot(1974:2022, tmp_aggregated/1000, type="l", main="", xlab="", ylab="", axes=FALSE, col="red")
  axis(4)
}
mtext(text = "Year",1,outer=T,line=0.5)
mtext(text = "weight obs (kg)",2,outer=T,line=0.5)
mtext(text = "weight mizer (kg)",4,outer=T,line=-0.5)

##now plotting the cohort plot 2.4
#this function is required below, but only for the cohort plot and has been replaced elsewhere with a better one
get_numbers_at_age <- function(input,max_ages=20){
  sim <- input@params
  waa <- input@waa
  years <- dim(waa)[1]
  nspec <- nrow(sim@species_params)
  ret <- array(FALSE,dim=c(years,nspec,max_ages),
               dimnames = list(rownames(input@n),colnames(input@n),c(1:max_ages)))
  num_at_age <- getNumbers(input)
  
  for(i in 1:years){
    for(j in 1:nspec){
      for(k in 1:(max_ages)){
        
        checkwaa <- waa[i,j,k]
        
        waa_index <- max(which(sim@w <= checkwaa))
        
        w0 <- sim@w[(waa_index)]
        #WHAT IF ITS IN THE MAX SIZE CLASS? - or the maximum populated size class.
        bigN <- input@n[i,j,min(waa_index+1, length(sim@w))]
        
        littleN <- input@n[i,j,(waa_index)]
        
        dw <- sim@dw[(waa_index)]
        
        #if(i==3 & j==1 & k==15){
        #  browser()
        #}
        
        if (is.na(bigN) || bigN == 0){
          #this code is a repeat, and is required as once the end of the size spectrum is reached (species or community)
          #the next value is 0 for bigN, which will return an error due to log(0)
          bigN <- input@n[i,j,(waa_index)]
          littleN <- input@n[i,j,(waa_index-1)]
          grad <- (log(bigN)-log(littleN))/(log(w0+dw)-log(w0))
          interZ <- (littleN*dw*(grad+1))/(((w0+dw)^(grad + 1) - w0^(grad + 1)))
          slither <- (interZ/(grad+1))*((checkwaa)^(grad+1)-w0^(grad+1))
          previous <- sum(num_at_age[i,j,head(which(sim@w <= checkwaa), -1)])
          ret[i,j,k] <- slither + previous
          next
        } 
        
        
        grad <- (log(bigN)-log(littleN))/(log(w0+dw)-log(w0))
        
        interZ <- (littleN*dw*(grad+1))/(((w0+dw)^(grad + 1) - w0^(grad + 1)))
        
        slither <- (interZ/(grad+1))*((checkwaa)^(grad+1)-w0^(grad+1))
        
        
        previous <- sum(num_at_age[i,j,head(which(sim@w <= checkwaa), -1)])
        
        
        
        ret[i,j,k] <- slither + previous
        
      }
    }
  }
  
  #this is calculating the difference
  retdiff <- ret
  
  for (i in seq_len(dim(ret)[1])) {
    for (j in seq_len(dim(ret)[2])) {
      for (k in seq_len(dim(ret)[3])){
        
        retdiff[i, j, k] <-  ret[i, j, k]-ret[i, j, max(k-1,1)]
        
        retdiff[i,j,1] <- ret[i,j,1]
        
      }
    }
  }
  
  
  return(retdiff)
}

waa <- get_numbers_at_age(projection)
release=1
waa <- waa[-1,,]
df <- waa
testarray <- array(dim=dim(waa))
group <- rep(1:ceiling(nrow(waa[,1,])/10), each = 10)[1:nrow(waa[,1,])]
#set the numbers
#I split into groups of 10 because the agetesters are released every year, and there are 10 timesaves in a year. 

generate_sequential_df <- function(df, start_value) {
  ncol <- ncol(df)
  nrow <- nrow(df)
  new_values <- matrix(rep(start_value:1, each = nrow), nrow = nrow, ncol = ncol, byrow = FALSE)
  return(as.data.frame(new_values))
}

for( i in 1:dim(df)[2]){
  splitwaa <- as.data.frame(df[,i,])%>%
    split(.,group)%>%{ 
      split_list <- .
      lapply(seq_along(split_list), function(i) {
        generate_sequential_df(split_list[[i]], start_value = ncol(split_list[[i]]) + (i - 1))
      })
    }%>%do.call(rbind, .)
  testarray[,i,] <- as.matrix(splitwaa)
}
dimnames(testarray) <- dimnames(df)[]

testmelt <- melt(testarray, varnames = c("time", "species", "testernumber"))
fullmelt <- melt(df, varnames = c("time", "species", "testernumber"))
combined_df <- fullmelt %>%
  left_join(testmelt, by = c("time", "species", "testernumber"))

combined_df <- combined_df %>%
  group_by(value.y, species)%>%
  arrange(time)%>%
  mutate(bday = first(time)-0.1)%>%
  mutate(integer_age = floor(time - bday),
         age = (time - bday))

p_main <- ggplot(combined_df%>%filter(species=="Whiting", age > 1))+
  geom_line(aes(x=as.numeric(time), y = value.x, group = value.y), na.rm = TRUE)+
  scale_x_continuous(limits = c(1986, 2020))+
  labs(x = "", y = "Individuals")+
  scale_y_log10()+
  theme_minimal()+
  theme(axis.title.x = element_blank(),
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank())
#this is just the historic fishing Ms, which have been transformed to work ona sec_axis
f_df <- data.frame(
  Year = 1984:2019,
  F = c(0.800, 0.772, 0.837, 0.947, 0.807, 0.869, 0.786, 0.660, 0.625, 0.671,
        0.694, 0.656, 0.603, 0.493, 0.449, 0.508, 0.577, 0.472, 0.372, 0.298,
        0.247, 0.216, 0.243, 0.227, 0.216, 0.246, 0.282, 0.251, 0.253, 0.247,
        0.284, 0.320, 0.318, 0.275, 0.229, 0.226),
  F_trans = c(6.337142e+10, 2.245931e+10, 2.495704e+11, 1.468936e+13, 8.213300e+10,
              8.166705e+11, 3.772636e+10, 3.543303e+08, 9.689180e+07, 5.325854e+08,
              1.248649e+09, 3.055284e+08, 4.288694e+07, 7.286439e+05, 1.427550e+05,
              1.270144e+06, 1.636841e+07, 3.346899e+05, 8.236157e+03, 5.310376e+02,
              8.027442e+01, 2.545731e+01, 6.921822e+01, 3.826428e+01, 2.545731e+01,
              7.735493e+01, 2.935611e+02, 9.309661e+01, 1.002564e+02, 8.027442e+01,
              3.161381e+02, 1.199740e+03, 1.114061e+03, 2.265031e+02, 4.120709e+01,
              3.687265e+01)
)


p_F1 <- ggplot(f_df, aes(x = Year, y = F)) +
  geom_line(color = "red", size = 1) +
  scale_x_continuous(limits = c(1986, 2020))+
  labs(x = "Year", y = "F") +
  theme_minimal()
 p_main / (p_F1)

###now plotting fig 2.5
##ret is a mtrix populated by each of the runs with different dts and no_w - the first one which is used for this plot is 0.1 and 100
 
 get_grad_interZ <- function(waa_index,input,sim,i,j){
   ####
   bigN <- input@n[i,j,min(waa_index+1, length(sim@w))]
   if(bigN==0){
     waa_index <- waa_index-1
     bigN <- input@n[i,j,min(waa_index+1, length(sim@w))]
   }
   littleN <- input@n[i,j,(waa_index)]
   w0 <- sim@w[(waa_index)]
   dw <- sim@dw[(waa_index)]
   grad <- (log(bigN)-log(littleN))/(log(w0+dw)-log(w0))
   #interZ <- (littleN*dw*(grad+1))/(((w0+dw)^(grad + 1) - w0^(grad + 1)))
   #return(c(grad,interZ))
   return(grad)
 }
 
 prop_lower <- function(w_a_a,grad,waa_index,sim){
   w0 <- sim@w[(waa_index)]
   dw <- sim@dw[(waa_index)]
   pows <- c(w_a_a,w0,w0+dw)^(grad+1)
   (pows[1]-pows[2]) / (pows[3] - pows[2])
 }
 
 get_prop_at_age_at_size <- function(input,max_ages=20){
   sim <- input@params
   waa <- input@waa
   years <- dim(waa)[1]
   nspec <- nrow(sim@species_params)
   ret <- array(FALSE,dim=c(years,nspec,max_ages,length(sim@w)),
                dimnames = list(rownames(input@n),colnames(input@n),c(1:max_ages),sim@w))
   for(i in 1:years){
     for(j in 1:nspec){
       ret_inner <- matrix(0,max_ages,length(sim@w))
       checkwaa <- waa[i,j,]
       tester_boundary <- sapply(checkwaa,function(x){max(which(sim@w <= x))})
       get_mod_shapes <- sapply(tester_boundary,get_grad_interZ,input=input,sim=sim,i=i,j=j)
       for(k in 1:(max_ages-1)){
         ret_inner[k,1:(tester_boundary[k]-1)] <- 1
         ret_inner[k,tester_boundary[k]] <- prop_lower(checkwaa[k],get_mod_shapes[k],tester_boundary[k],sim)
       }
       ret_inner[max_ages,] <- 1
       ret[i,j,,] <- apply(rbind(0,ret_inner),2,diff)
     }
   }
   return(ret)
 }
 
 get_num_at_age <- function(prop_at_age_at_size,num_at_size,max_ages=20){
   num_at_age <- array(0,dim=c(dim(num_at_size)[1:2],max_ages))
   for(i in 1:nrow(num_at_age)){
     for(j in 1:(dim(num_at_age)[2])){
       num_at_age[i,j,] <- t(as.matrix(num_at_size[i,j,])) %*% t(prop_at_age_at_size[i,j,,]) 
     }
   }
   return(num_at_age)
 }
 
 get_catch_at_age <- function(prj,prop_at_age_at_size,num_at_size,max_ages=20,dt=0.1,use_after=TRUE){
   Fmort<-getFMort(prj)
   catch_at_age <- array(0,dim=c(dim(num_at_size)[1:2]-c(1,0),max_ages))
   if(use_after){
     F_num_at_size <- num_at_size[-1,,] * Fmort[-nrow(Fmort),,] *dt
   }else{
     F_num_at_size <- num_at_size[,,] * Fmort[,,] *dt
   }
   for(i in 1:nrow(catch_at_age)){
     for(j in 1:(dim(num_at_size)[2])){
       catch_at_age[i,j,] <- t(as.matrix(F_num_at_size[i,j,])) %*% t(prop_at_age_at_size[i,j,,]) 
     }
   }
   return(catch_at_age)
 }
 
 get_catch_by_year_by_age <- function(catch_at_age,dt=0.1){
   nyears <- nrow(catch_at_age)*dt
   catch_by_year_by_age <- array(0,dim=c(nyears,dim(catch_at_age)[2:3]))
   for(i in 1:nyears){
     catch_by_year_by_age[i,,] <- apply(catch_at_age[(1:(1/dt)) + (i-1)*(1/dt),,],c(2,3),sum)
   }
   return(catch_by_year_by_age)
 }
 
 get_num_by_year_by_age<-function(num_at_age,dt=0.1){
   nyears <- floor(nrow(num_at_age)*dt)
   num_by_year_by_age <- array(0,dim=c(nyears+1,dim(num_at_age)[2:3]))
   for(i in 1:(nyears+1)){
     num_by_year_by_age[i,,] <- num_at_age[1 + (i-1)*(1/dt),,]
   }
   return(num_by_year_by_age)
 }
 
 
 get_Zs <- function(num_by_year_by_age){
   Zs <- 0 * num_by_year_by_age[-1,,-1]
   for(i in 1:dim(Zs)[1]){
     Zs[i,,] <- -log(num_by_year_by_age[i+1,,-1]) + log(num_by_year_by_age[i,,-dim(num_by_year_by_age)[3]])
   }
   return(Zs) ### note age zero Zs will be negative as numbers in lowest age increase
 }
 
 get_Fs <- function(catch_by_year_by_age,num_by_year_by_age, Zs){
   catches <- catch_by_year_by_age[,,-dim(catch_by_year_by_age)[3]] ## remove last
   Fs <- catches * Zs / (num_by_year_by_age[-nrow(num_by_year_by_age),,-dim(num_by_year_by_age)[3]] * (1 - exp(-Zs)))
   return(Fs)
 }
 
 get_Ms <- function(Zs,Fs){
   return(Zs-Fs)
 }
 
 get_morts <- function(prj,dt){
   prop_at_age_at_size <- get_prop_at_age_at_size(prj)
   num_at_size <- getNumbers(prj)
   num_at_age <- get_num_at_age(prop_at_age_at_size,num_at_size)
   catch_at_age <- get_catch_at_age(prj,prop_at_age_at_size,num_at_size,dt=dt)
   catch_by_year_by_age <- get_catch_by_year_by_age(catch_at_age,dt=dt)
   num_by_year_by_age <- get_num_by_year_by_age(num_at_age,dt=dt)
   Zs <- get_Zs(num_by_year_by_age)
   Fs <- get_Fs(catch_by_year_by_age,num_by_year_by_age, Zs)
   Ms <- get_Ms(Zs,Fs)
   return(list(Zs=Zs,Fs=Fs,Ms=Ms))
 }
 
 ret <- matrix(list(c()),3,3)
 
 dts <- c(0.1,0.01,0.001)
 ws <- c(100,1000,2000)
 pas<-cbind(rep(dts,times=3),rep(ws,each=3))
 
 #these contain the data for mizer simulations at the dts and ws specified above. run them using the
 #above code - then load them in here. 
 for(i in 1:3){
   for(j in 1:3){
     load(paste("run",dts[i],"_",ws[j],".Rdata",sep=""))
     ret[i,j][[1]] <- get_morts(sim,dts[i])
   }
 }

 #par(mfrow=c(3,1))
 cols <- c("red","darkred","blue","darkblue")
 layout(matrix(c(1,2,3,4,4,4),3,2),widths=c(5,1))
 par(mar=c(2,4,2,1))
 par(oma=c(1,1,1,0))
 plot(1:20,1:20,ylim=c(range(ret[1,1][[1]]$Zs[,6,2:5])),xlim=c(1985,2019),type="n",xlab="",ylab="Z")
 for(i in 2:5){
   lines(1985:2019,ret[1,1][[1]]$Zs[-1,6,i],col=cols[i-1])
 }
 plot(1:20,1:20,ylim=c(range(ret[1,1][[1]]$Fs[-1,6,2:5])),type="n",xlab="",ylab="F",xlim=c(1985,2019),)
 for(i in 2:5){
   lines(1985:2019,ret[1,1][[1]]$Fs[-1,6,i],col=cols[i-1])
 }
 plot(1:20,1:20,ylim=c(range(ret[1,1][[1]]$Ms[-1,6,2:5])),type="n",xlab="",ylab="M",xlim=c(1985,2019),)
 for(i in 2:5){
   lines(1985:2019,ret[1,1][[1]]$Ms[-1,6,i],col=cols[i-1])
 }
 par(mar=c(0,0,0,0))
 plot(1,1,type="n",axes=F,xlab="",ylab="")
 legend("left",legend = c("Age 1","Age 2","Age 3","Age 4"),col=cols,lty=1)
 
 
 ######
 
 
 #fig 3.1
 
 
 #first need to load in a function that does the same as mizers a/b in cpp - for speed
 cppFunction(code='
 #include <Rcpp.h>
 using namespace Rcpp;
 
 // [[Rcpp::export]]
 NumericMatrix fullProjectionLoop(double years, double dt,
                                  NumericVector gs, NumericVector dw,
                                  NumericVector initial_num) {
   // Number of time steps = years/dt
   int nsteps = static_cast<int>(years / dt);
   int n_w = initial_num.size();
   // Prepare output matrix: each row is a snapshot of "num"
   NumericMatrix nums(nsteps, n_w);
   // Work on a copy of the initial state
   NumericVector num = clone(initial_num);
   NumericVector A(n_w);
   NumericVector B(n_w);
   A(0)=0.0;
   B(0)=(1 + dt * gs[0] / dw[0]);
   for (int i = 1; i < n_w; i++) {
     // In the R code: A = dt * -gs[i-1] / params@dw[i]
     //               B = 1 + dt * gs[i] / params@dw[i]
     A(i) = dt * (-gs[i - 1]) / dw[i];
     B(i) = 1 + dt * gs[i] / dw[i];
   }
   for (int t = 0; t < nsteps; t++) {
     // Update from second element (index 1) to last element
     num[0] = num[0]/B(0);
     for (int i = 1; i < n_w; i++) {
       num[i] = (num[i] - A(i) * num[i - 1]) / B(i);
     }
     for (int i = 0; i < n_w; i++) {
       nums(t, i) = num[i];
     }
   }
   return nums;
 }
 ')
 
 # function that takes a vector of dt and w - calculates the growth rate - 
 dt_w_values <- function(dt, w){
   
   years <- 5
   spec <- 8
   values <- expand.grid(dt, w)
   mean_waa_t <- data.frame(matrix(nrow = nrow(values), ncol = 3))
   
   for (i in 1:nrow(values)){
     
     dt <- values[i,1]
     params <- newMultispeciesParams(species_params = params@species_params, no_w = (values[i,2]))
     
     allgrow <- getEGrowth(params)
     gs <- allgrow[spec,]
     
     num <- rep(0,length(params@w))
     num[1] <- 1 / params@dw[1]
     
     dw <- params@dw 
     nums <- fullProjectionLoop(years, dt, gs, dw, num)
     
     waa <- sim@waa
     waa[1,spec,1] <- params@w[1]
     waa <- waa[1,,1:2]
     
     #print(length(nums))
     
     save_spec <- c()
     waat_t <- c()
     k <- 0
     while(k<(years/dt)){
       #print(k)
       #print(years/dt)
       k <- k+1
       waa <- new_waa(waa, allgrow, dt, params@w, spec)
       save_spec <- c(save_spec, waa[spec,1])
       waat_t <- c(waat_t,(sum(((nums[k,]*params@dw)/
                                  (sum(nums[k,]*params@dw)))[params@w<waa[spec,1]])))
       
       #if(k == nrow(nums)){k <- years/dt}
       
     }
     
     #save waa_t avg
     mean_waa_t[i,1] <- mean(waat_t)
     mean_waa_t[i,2] <- values[i,2]
     mean_waa_t[i,3] <- values[i,1]
   }
   return(mean_waa_t)
 }
 
 dt_vec <- c(10^seq(log10(0.1), log10(0.0001), length.out = 5))  # Midpoint included
 w_vec <- c(10^seq(log10(100), log10(10000), length.out = 5))  # Two midpoints included
 
 dt_w_grid <- dt_w_values((1/(floor(1/dt_vec))), round(w_vec))
 
 dt_w_grid$Label <- formatC(dt_w_grid$X1, format = "f", digits = 2)
 dt_w_grid$X2 <- signif(dt_w_grid$X2, 2)
 dt_w_grid$X3 <- signif(dt_w_grid$X3, 2)
 
 ggplot(dt_w_grid, aes(x = as.factor(X2), y = as.factor(X3), fill = X1)) +
   geom_tile()+
   geom_text(aes(label = Label), color = "black", size = 5) +
   scale_fill_viridis_c(alpha = 0.75)+
   labs(x = "Number of w classes", y = "dt", fill = "Quantile") +
   theme_minimal() +
   theme(axis.text.x = element_text(angle = 45, hjust = 1))
 
 
 
#fig 3.2
#getting data - same as above
 res<-matrix(list(c()),3,3)
 dts <- c(0.1,0.01,0.001)
 nw <- c(100,1000,10000)
 for(i in 1:3){
   params <- newMultispeciesParams(NS_params@species_params, no_w = nw[i])
   allgrow <- getEGrowth(params)
   gs <- allgrow[spec,]
   for (j in 1:3){
     num <- rep(0,length(params@w))
     num[1] <- 1 / params@dw[1]
     res[j,i] <- list(fullProjectionLoop(10,dts[j],gs,params@dw,num))
   }
 }
 
 params_list <- rep(list(c()),3)
 for(i in 1:3){
   params <- newMultispeciesParams(NS_params@species_params, no_w = nw[i])
   params_list[[i]] <- list(w=params@w,dw=params@dw)
 }
 
 cols <- c("black","darkblue","darkred")
 
 par(mfcol=c(3,2))
 par(mar=c(3,3,2,1))
 par(oma=c(1,3.5,1,1))
 for(k in c(1,4)){
   #dat <- get_max(res,k)
   get_dt <- k / dts[1]
   tmp<-cumsum(res[1,1][[1]][get_dt,])
   range_x <- intersect(which(tmp > (tail(tmp,n=1) * 0.001)),which(tmp < (tail(tmp,n=1) * 0.999)))
   for(i in 1:3){
     get_dt <- k / dts[3]
     maxy<-max(res[3,i][[1]][get_dt,])
     plot(1,1,type="n",xlim=range(params_list[[1]]$w[range_x]),ylim=c(0,maxy),log="x",main="")
     for(j in 1:3){
       get_dt <- k / dts[j]
       lines(params_list[[i]]$w,res[j,i][[1]][get_dt,],col=cols[j],lty=1,lwd=2)
     }
     if(i==1){
       mtext(paste("age", k),side = 3,line=0.5)
     }
     if(k==1){
       mtext(paste("n_w = ",nw[i],sep=""),side = 2,line=2.7)
     }
   } 
 }
 mtext("w",side=1,outer=T)
 mtext("Density",side=2,outer=T,line=2)
 
 #table 3
 
 #this code was ran to get the sims of different dt and dw, then the Z,F,M was calculated with the functions above.
 
 histF <- read.csv("historicfishingM.csv")[,-1]
 Fs<-histF[,c(12,1,2,3,10,4,5,11,6,7,8,9)]
 
 get_sim_object <- function(pas){
   NS_species <- NS_species_params_gears
   NS_species$b <- c(3.014,3.32,2.941,3.429,2.986,3.080,3.019,3.198,3.010,3.160,3.173,3.075)
   NS_species$alpha <- 0.6
   NS_species$f0 <- 0.6
   NS_species$a <- c(0.007,0.001,0.009,0.002,0.010,0.006,0.008,0.004,0.007,0.005,0.005,0.007)
   
   
   params <- newMultispeciesParams(NS_species, interaction = NS_params@interaction,kappa=1e11,no_w = pas[2])
   dt <- pas[1]
   gear_params(params) <- data.frame(
     species = c("Sprat", "Sandeel", "N.pout", "Herring", "Dab", "Whiting", 
                 "Sole", "Gurnard", "Plaice", "Haddock", "Cod", "Saithe"),
     gear = c("Sprat", "Sandeel", "N.pout", "Herring", "Dab", "Whiting", 
              "Sole", "Gurnard", "Plaice", "Haddock", "Cod", "Saithe"),
     sel_func = rep("sigmoid_length", 12),
     catchability = rep(1, 12),
     l25=c(7.65,11.52,19.810,9.83,8.690,10.130,19.81,16.4,11.52,19.09,13.2,35.32),
     l50 = c(8.14,17.04,29.02,11.82,12.40,20.79,29.02,25.8,17.04,24.34,22.87,43.55),
     stringsAsFactors = FALSE
   )
   new_Fs <- sapply(Fs,function(x){rep(x,each=1/dt)})
   new_Fs <- rbind(new_Fs,0)
   colnames(new_Fs) <- c("Sprat", "Sandeel", "N.pout", "Herring", "Dab", "Whiting", 
                         "Sole", "Gurnard", "Plaice", "Haddock", "Cod", "Saithe")
   rownames(new_Fs) <- seq(dt,by=dt,length.out=(1/dt)*nrow(Fs)+1)
   ### run for 80 years
   sim <- mizer::project(params,effort=new_Fs[1,],dt=dt,t_max=80)
   sim <- project(params,effort=new_Fs[1,],dt=dt,initial_n = sim@n[nrow(sim@n),,],initial_n_pp = sim@n_pp[nrow(sim@n_pp),],t_max=20)
   sim <- project(params,effort=new_Fs,dt=dt,initial_n = sim@n[nrow(sim@n),,],initial_n_pp = sim@n_pp[nrow(sim@n_pp),],waa_initial = sim@waa[nrow(sim@waa),,],t_save = dt)
   save(sim,file=paste("run",dt,"_",pas[2],".Rdata",sep=""))
 }
 
 dts <- c(0.1,0.01,0.001)
 ws <- c(100,1000,2000)
 
 pas<-cbind(rep(dts,times=3),rep(ws,each=3))
 
 apply(pas[6:9,],1,get_sim_object)
 

 