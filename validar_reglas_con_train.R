# ================================================================
# Taller grupal 1 - Validacion de reglas n => 1 con train
# ================================================================
#
# Este script NO aprende reglas nuevas. Toma las reglas ya aprendidas con
# order_products__prior.csv y pregunta si esas mismas asociaciones aparecen
# tambien en order_products__train.csv.
#
# Flujo:
# prior -> aprender reglas n => 1 -> guardar objetos .rds
# train -> medir soporte, confianza y lift de esas reglas -> validar
#
# Ejemplo: si prior aprendio {pasta sauce} => {dry pasta}, este script calcula
# P(dry pasta | pasta sauce) de nuevo, pero usando unicamente ordenes train.
# ================================================================

# -------------------------
# 0. Paquetes
# -------------------------
instalar_si_falta <- function(paquete) {
  if (!requireNamespace(paquete, quietly = TRUE)) {
    install.packages(paquete, repos = "https://cloud.r-project.org")
  }
}

paquetes <- c("data.table", "arules")
invisible(lapply(paquetes, instalar_si_falta))

library(data.table)
library(arules)

# -------------------------
# 1. Rutas
# -------------------------
argumentos <- commandArgs(trailingOnly = FALSE)
indice_archivo <- grep("^--file=", argumentos)
if (length(indice_archivo) > 0) {
  ruta_script <- normalizePath(sub("^--file=", "", argumentos[indice_archivo[1]]))
  ruta_proyecto <- dirname(ruta_script)
} else {
  ruta_proyecto <- getwd()
}

ruta_datos <- file.path(ruta_proyecto, "instacart_2017_05_01")
ruta_reglas <- file.path(ruta_proyecto, "salida_apriori")
ruta_salida <- file.path(ruta_proyecto, "salida_validacion_train")
dir.create(ruta_salida, showWarnings = FALSE)

stopifnot(dir.exists(ruta_datos), dir.exists(ruta_reglas))

# -------------------------
# 2. Funciones de validacion
# -------------------------
validar_reglas <- function(reglas, transacciones_train, etiqueta, max_n,
                            ruta_salida) {
  if (length(reglas) == 0) {
    message("No hay reglas de ", etiqueta, " para validar.")
    return(NULL)
  }

  # interestMeasure recalcula cada métrica con las transacciones train.
  # reuse = FALSE evita reutilizar las métricas que fueron aprendidas en prior.
  soporte_train <- interestMeasure(
    reglas, transactions = transacciones_train,
    measure = "support", reuse = FALSE
  )
  confianza_train <- interestMeasure(
    reglas, transactions = transacciones_train,
    measure = "confidence", reuse = FALSE
  )
  lift_train <- interestMeasure(
    reglas, transactions = transacciones_train,
    measure = "lift", reuse = FALSE
  )

  tabla <- as(reglas, "data.frame")
  setDT(tabla)
  setnames(tabla,
           old = c("support", "confidence", "lift"),
           new = c("support_prior", "confidence_prior", "lift_prior"))

  tabla[, `:=`(
    n_antecedente = size(lhs(reglas)),
    n_consecuente = size(rhs(reglas)),
    support_train = soporte_train,
    confidence_train = confianza_train,
    lift_train = lift_train,
    count_train = round(soporte_train * length(transacciones_train))
  )]
  tabla[, ratio_support_train_prior := support_train / support_prior]
  tabla[, estado_validacion := fifelse(
    is.na(lift_train), "No estimable en train",
    fifelse(lift_train > 1, "Asociacion positiva replicada",
           "No se replica como asociacion positiva")
  )]

  resumen <- tabla[, .(
    nivel = etiqueta,
    reglas_evaluadas = .N,
    soporte_prior_promedio = mean(support_prior, na.rm = TRUE),
    soporte_train_promedio = mean(support_train, na.rm = TRUE),
    confianza_prior_promedio = mean(confidence_prior, na.rm = TRUE),
    confianza_train_promedio = mean(confidence_train, na.rm = TRUE),
    lift_prior_promedio = mean(lift_prior, na.rm = TRUE),
    lift_train_promedio = mean(lift_train, na.rm = TRUE),
    reglas_lift_train_mayor_1 = sum(lift_train > 1, na.rm = TRUE),
    proporcion_lift_train_mayor_1 = mean(lift_train > 1, na.rm = TRUE)
  ), by = n_antecedente]

  for (n in seq_len(max_n)) {
    tabla_n <- tabla[n_antecedente == n]
    if (nrow(tabla_n) == 0) next

    nombre_base <- paste0("validacion_", etiqueta, "_", n, "_a_1")
    fwrite(tabla_n, file.path(ruta_salida, paste0(nombre_base, "_todas.csv")))
    fwrite(head(tabla_n[order(-lift_train, -support_train)], 30),
           file.path(ruta_salida, paste0(nombre_base, "_top_lift_train.csv")))
    fwrite(head(tabla_n[order(-support_train, -lift_train)], 30),
           file.path(ruta_salida, paste0(nombre_base, "_top_soporte_train.csv")))
  }

  resumen
}

crear_transacciones_train <- function(items_train, columna_elemento) {
  canastas <- items_train[
    , .(elementos = list(unique(get(columna_elemento)))),
    by = order_id
  ]
  lista_canastas <- setNames(canastas$elementos, canastas$order_id)
  as(lista_canastas, "transactions")
}

# -------------------------
# 3. Cargar las reglas aprendidas con prior
# -------------------------
# Estos .rds se crean al ejecutar instacart_apriori_paso_a_paso.R actualizado.
archivos_reglas <- list(
  producto = file.path(ruta_reglas, "reglas_producto_n_a_1.rds"),
  pasillo = file.path(ruta_reglas, "reglas_pasillo_n_a_1.rds")
)

faltantes <- names(archivos_reglas)[!file.exists(unlist(archivos_reglas))]
if (length(faltantes) > 0) {
  stop(
    "Faltan los objetos de reglas para: ", paste(faltantes, collapse = ", "),
    ". Ejecute primero instacart_apriori_paso_a_paso.R actualizado."
  )
}

rules_producto <- readRDS(archivos_reglas$producto)
rules_pasillo <- readRDS(archivos_reglas$pasillo)

# -------------------------
# 4. Construir canastas futuras desde train
# -------------------------
# train tiene productos de órdenes posteriores. No se usa para aprender reglas;
# se usa únicamente para recalcular sus métricas y verificar su estabilidad.
train <- fread(
  file.path(ruta_datos, "order_products__train.csv"),
  select = c("order_id", "product_id", "add_to_cart_order", "reordered")
)
products <- fread(file.path(ruta_datos, "products.csv"))
aisles <- fread(file.path(ruta_datos, "aisles.csv"))

items_train <- merge(train, products, by = "product_id", all.x = TRUE)
items_train <- merge(items_train, aisles, by = "aisle_id", all.x = TRUE)

transacciones_train_producto <- crear_transacciones_train(items_train, "product_name")
transacciones_train_pasillo <- crear_transacciones_train(items_train, "aisle")

cat("Ordenes train para validar:", length(transacciones_train_producto), "\n")

# -------------------------
# 5. Validar producto y pasillo por separado
# -------------------------
MAX_ANTECEDENTE_PRODUCTO <- max(size(lhs(rules_producto)))
MAX_ANTECEDENTE_PASILLO <- max(size(lhs(rules_pasillo)))

resumen_producto <- validar_reglas(
  rules_producto, transacciones_train_producto, "producto",
  MAX_ANTECEDENTE_PRODUCTO, ruta_salida
)
resumen_pasillo <- validar_reglas(
  rules_pasillo, transacciones_train_pasillo, "pasillo",
  MAX_ANTECEDENTE_PASILLO, ruta_salida
)

resumen_validacion <- rbindlist(list(resumen_producto, resumen_pasillo),
                                 fill = TRUE)
fwrite(resumen_validacion,
       file.path(ruta_salida, "resumen_validacion_train.csv"))

cat("\nProceso terminado. Revise la carpeta:\n", ruta_salida, "\n")
