# Generates the figures used in the mizer 3.4 announcement.
# Run from anywhere with mizer 3.4 installed.
library(mizer)
library(ggplot2)

out <- normalizePath(".", mustWork = TRUE)
save_fig <- function(name, plot) {
    ggsave(file.path(out, name), plot, width = 7, height = 4.5, dpi = 150)
}

## 1. Steady-state residual after a calibration / matching step -------------
params_unsteady <- matchGrowth(NS_params)
p_res <- plot(getSteadyResidual(params_unsteady))
save_fig("residual.png", p_res)
save_fig("preview.png", p_res)

## 2. Shift in length-based gear selectivity with defaulted allometry -------
sp_custom <- NS_species_params
gp_length <- data.frame(
    gear = "Trawl",
    species = "Cod",
    sel_func = "sigmoid_length",
    l50 = 50,
    l25 = 40,
    catchability = 1
)
params_true <- newMultispeciesParams(sp_custom, gear_params = gp_length, info_level = 0)
sp_default_ab <- sp_custom
sp_default_ab$a <- NULL
sp_default_ab$b <- NULL
params_default <- newMultispeciesParams(sp_default_ab, gear_params = gp_length, info_level = 0)

w <- params_true@w
sel_true <- params_true@selectivity["Trawl", "Cod", ]
sel_default <- params_default@selectivity["Trawl", "Cod", ]

df_sel <- rbind(
    data.frame(Weight = w, Selectivity = sel_true, Allometry = "Supplied (a = 0.0078, b = 3.05)"),
    data.frame(Weight = w, Selectivity = sel_default, Allometry = "Defaulted (a = 0.01, b = 3)")
)
p_sel <- ggplot(df_sel, aes(x = Weight, y = Selectivity, color = Allometry, linetype = Allometry)) +
    geom_line(linewidth = 1) +
    scale_x_log10(name = "Body weight [g]", labels = scales::label_comma()) +
    scale_y_continuous(name = "Selectivity", limits = c(0, 1.05)) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "bottom",
          plot.title = element_text(face = "bold", size = 13)) +
    labs(title = "Selectivity for 50 cm Cod: Supplied vs Defaulted Allometry",
         subtitle = "Defaulting a and b misplaces the selectivity curve along the weight axis")

save_fig("selectivity-shift.png", p_sel)

## 3. Encounter rates over species size ranges matching summary() -----------
p_enc <- plot(getEncounter(NS_params))
save_fig("encounter-rate.png", p_enc)
