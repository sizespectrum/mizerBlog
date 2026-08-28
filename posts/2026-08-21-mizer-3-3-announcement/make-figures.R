# Generates the figures used in the mizer 3.3 announcement.
# Run from anywhere with mizer 3.3 installed (or devtools::load_all() on the
# mizer source tree).
library(mizer)
library(ggplot2)

out <- normalizePath(".", mustWork = TRUE)
save_fig <- function(name, plot) {
    ggsave(file.path(out, name), plot, width = 7, height = 4.5, dpi = 150)
}

## 1. Steady-state residual after a calibration step -------------------------
params_matched <- matchGrowth(NS_params)
save_fig("residual.png", plot(getSteadyResidual(params_matched)))

## 2. The limit cycle beyond the Hopf bifurcation ---------------------------
sim_cycle <- projectUntilSettled(NS_params, effort = 1.5, t_max = 200,
                                 t_save = 0.2, method = "tr_bdf2")
save_fig("limit-cycle.png", plotBiomass(sim_cycle))
save_fig("preview.png", plotBiomass(sim_cycle))

## 3. Yield against fishing mortality, with F_MSY marked --------------------
save_fig("yield-vs-f.png",
         plotYieldVsF(NS_params, species = "Cod", progress_bar = FALSE))

## 4. Spectra on a length axis, now with resource and total -----------------
save_fig("length-spectra.png",
         plotSpectra(NS_params, size_axis = "l", power = 2, total = TRUE))
