# ================================================================
# Taller grupal 1 - Instacart
# Reglas de asociacion (Market Basket Analysis) con Apriori
# ================================================================
#
# IDEA CENTRAL
# Cada fila de order_products__prior.csv dice que un producto estuvo
# en una orden. Para Apriori, cada ORDEN se convierte en una CANASTA:
#
# Orden 10 -> {Bananas, Yogurt, Granola}
# Orden 11 -> {Milk, Eggs}
#
# A partir de esas canastas buscamos reglas A => B.
# - soporte:     P(A interseccion B)
# - confianza:   P(B dado A)
# - lift:        P(B dado A) / P(B)
#
# Este archivo se ejecuta desde RStudio con Source, o desde una terminal con:
# Rscript instacart_apriori_paso_a_paso.R
# ================================================================

# -------------------------
# 0. Paquetes de R
# -------------------------
# data.table lee archivos CSV grandes mucho mas rapido que read.csv.
# arules contiene Apriori y el tipo especial llamado "transactions".
# arulesViz permite graficar las reglas.
instalar_si_falta <- function(paquete) {
  if (!requireNamespace(paquete, quietly = TRUE)) {
    install.packages(paquete, repos = "https://cloud.r-project.org")
  }
}

paquetes <- c("data.table", "arules", "arulesViz")
invisible(lapply(paquetes, instalar_si_falta))

library(data.table)
library(arules)
library(arulesViz)

# -------------------------
# 1. Rutas y parametros
# -------------------------
# Se busca la carpeta de datos junto a este script. Si se ejecuta desde
# RStudio, tambien funciona si el directorio de trabajo es el proyecto.
argumentos <- commandArgs(trailingOnly = FALSE)
indice_archivo <- grep("^--file=", argumentos)
if (length(indice_archivo) > 0) {
  ruta_script <- normalizePath(sub("^--file=", "", argumentos[indice_archivo[1]]))
  ruta_proyecto <- dirname(ruta_script)
} else {
  ruta_proyecto <- getwd()
}

ruta_datos <- file.path(ruta_proyecto, "instacart_2017_05_01")
ruta_salida <- file.path(ruta_proyecto, "salida_apriori")
dir.create(ruta_salida, showWarnings = FALSE)

# Para aprender, use una muestra de 50.000 ordenes. La base completa tiene
# millones de ordenes y puede consumir mucha memoria. Cuando el flujo funcione,
# aumente este valor paulatinamente: 100000, 250000, etc.
N_ORDENES_MUESTRA <- 50000
SEMILLA <- 2026

# Umbrales iniciales. En una muestra de 50.000 ordenes, soporte 0.002 equivale
# aproximadamente a 100 canastas. No hay un valor universal: se ajustan luego
# de observar cuantas reglas se producen y si tienen sentido de negocio.
SOPORTE_MINIMO_PRODUCTO <- 0.002
CONFIANZA_MINIMA_PRODUCTO <- 0.15
SOPORTE_MINIMO_CATEGORIA <- 0.01
CONFIANZA_MINIMA_CATEGORIA <- 0.20

stopifnot(dir.exists(ruta_datos))

# -------------------------
# 2. Leer los archivos necesarios
# -------------------------
# No leemos order_products__train.csv aun: se reservara para evaluar en otro
# paso si las recomendaciones obtenidas con prior predicen la siguiente compra.
orders <- fread(
  file.path(ruta_datos, "orders.csv"),
  select = c("order_id", "user_id", "eval_set", "order_number",
             "order_dow", "order_hour_of_day")
)

prior <- fread(
  file.path(ruta_datos, "order_products__prior.csv"),
  select = c("order_id", "product_id", "add_to_cart_order", "reordered")
)

products <- fread(file.path(ruta_datos, "products.csv"))
aisles <- fread(file.path(ruta_datos, "aisles.csv"))
departments <- fread(file.path(ruta_datos, "departments.csv"))

cat("Ordenes leidas:", nrow(orders), "\n")
cat("Lineas de productos previos leidas:", nrow(prior), "\n")

# -------------------------
# 3. Elegir ordenes historicas
# -------------------------
# 'prior' significa que la orden hace parte del historial. Cada orden del
# conjunto 'train' es posterior a dicho historial y se usara despues para
# validacion temporal.
ordenes_prior <- orders[eval_set == "prior"]

set.seed(SEMILLA)
n_elegir <- min(N_ORDENES_MUESTRA, nrow(ordenes_prior))
ids_muestra <- sample(ordenes_prior$order_id, size = n_elegir, replace = FALSE)

# Nos quedamos solo con las lineas de producto de las ordenes elegidas.
items <- prior[order_id %in% ids_muestra]

# Agregamos nombres y categorias SOLO despues de tomar la muestra. Asi no se
# hace un join costoso sobre toda la tabla de decenas de millones de filas.
items <- merge(items, products, by = "product_id", all.x = TRUE)
items <- merge(items, aisles, by = "aisle_id", all.x = TRUE)
items <- merge(items, departments, by = "department_id", all.x = TRUE)

cat("Ordenes en la muestra:", uniqueN(items$order_id), "\n")
cat("Productos distintos en la muestra:", uniqueN(items$product_id), "\n")

# -------------------------
# 4. Tamano de las canastas: ¿hay espacio para combinaciones?
# -------------------------
# Una canasta con 1 producto no permite estudiar asociaciones. Una canasta con
# mas de 3 productos ya permite explorar reglas como {A, B} => C y, con mas
# prudencia, {A, B} => {C, D}.
#
# Primero contamos productos DISTINTOS por orden. Luego unimos user_id para
# responder dos preguntas diferentes:
# 1) ¿Cuantas ordenes tienen mas de 3 productos?
# 2) ¿Cuantos clientes tienen por lo menos una de esas ordenes?
tamano_canasta <- items[, .(n_productos = uniqueN(product_id)), by = order_id]
tamano_canasta <- merge(
  tamano_canasta,
  ordenes_prior[, .(order_id, user_id)],
  by = "order_id",
  all.x = TRUE
)

canastas_mas_de_tres <- tamano_canasta[n_productos > 3]
clientes_mas_de_tres <- uniqueN(canastas_mas_de_tres$user_id)
clientes_en_muestra <- uniqueN(tamano_canasta$user_id)

resumen_canastas <- data.table(
  indicador = c(
    "Ordenes analizadas",
    "Ordenes con mas de 3 productos",
    "Proporcion de ordenes con mas de 3 productos",
    "Clientes unicos analizados",
    "Clientes con al menos una canasta de mas de 3 productos",
    "Proporcion de clientes con al menos una canasta de mas de 3 productos"
  ),
  valor = c(
    nrow(tamano_canasta),
    nrow(canastas_mas_de_tres),
    nrow(canastas_mas_de_tres) / nrow(tamano_canasta),
    clientes_en_muestra,
    clientes_mas_de_tres,
    clientes_mas_de_tres / clientes_en_muestra
  )
)

cat("\n--- Tamano de las canastas ---\n")
print(resumen_canastas)
fwrite(resumen_canastas, file.path(ruta_salida, "resumen_canastas_mas_de_3.csv"))

# Esta distribucion muestra si tres productos es un umbral razonable o si se
# debe ajustar. Por ejemplo, una mediana de 5 indica que reglas 2 => 1 son
# plausibles para una parte importante de las ordenes.
distribucion_tamano_canasta <- tamano_canasta[, .N, by = n_productos][order(n_productos)]
fwrite(distribucion_tamano_canasta,
       file.path(ruta_salida, "distribucion_tamano_canastas.csv"))

# -------------------------
# 5. Exploracion muy basica
# -------------------------
# La frecuencia NO es aun una regla de asociacion. Sirve para saber cuales
# productos son comunes y para detectar nombres o categorias inesperadas.
top_productos <- items[, .N, by = .(product_id, product_name)][order(-N)][1:20]
top_productos[, proporcion_ordenes := N / uniqueN(items$order_id)]
fwrite(top_productos, file.path(ruta_salida, "top_20_productos.csv"))

top_categorias <- items[, .N, by = .(department, aisle)][order(-N)][1:20]
fwrite(top_categorias, file.path(ruta_salida, "top_20_categorias.csv"))

print(top_productos)

# -------------------------
# 6. Crear transacciones por producto
# -------------------------
# arules necesita una lista: cada elemento es una canasta y cada nombre de la
# lista identifica la orden. unique() evita repetir un producto por accidente.
productos_por_orden <- items[
  , .(productos = list(unique(product_name))),
  by = order_id
]

lista_productos <- setNames(
  productos_por_orden$productos,
  productos_por_orden$order_id
)
transacciones_producto <- as(lista_productos, "transactions")

cat("\nResumen de transacciones por producto:\n")
summary(transacciones_producto)

# Grafico de los productos mas frecuentes. La altura es la proporcion de
# canastas que contiene cada producto, es decir P(producto).
png(file.path(ruta_salida, "frecuencia_top_20_productos.png"),
    width = 1400, height = 800, res = 150)
itemFrequencyPlot(transacciones_producto, topN = 20, type = "relative",
                  cex.names = 0.75,
                  main = "Productos mas frecuentes en las canastas")
dev.off()

# -------------------------
# 7. Minar reglas de producto
# -------------------------
# maxlen = 2 restringe inicialmente a pares A => B. Es recomendable aprender
# con pares antes de buscar triples como {A, B} => C, que son mas dificiles de
# interpretar y producen muchas combinaciones.
rules_producto <- apriori(
  transacciones_producto,
  parameter = list(
    support = SOPORTE_MINIMO_PRODUCTO,
    confidence = CONFIANZA_MINIMA_PRODUCTO,
    minlen = 2,
    maxlen = 2,
    target = "rules"
  )
)

cat("\nNumero de reglas producto => producto:", length(rules_producto), "\n")

if (length(rules_producto) == 0) {
  message("No se generaron reglas. Pruebe un soporte o confianza menores.")
} else {
  # Ordenar por lift prioriza asociaciones por encima de la popularidad base.
  rules_lift <- sort(rules_producto, by = "lift", decreasing = TRUE)
  top_reglas_producto <- head(rules_lift, 30)
  inspect(top_reglas_producto)

  # Exportar permite abrir las reglas en Excel y documentar la interpretacion.
  reglas_producto_df <- as(top_reglas_producto, "data.frame")
  fwrite(reglas_producto_df,
         file.path(ruta_salida, "top_30_reglas_producto_por_lift.csv"))

  # Un segundo listado por soporte privilegia reglas de mayor cobertura.
  reglas_soporte_df <- as(head(sort(rules_producto, by = "support",
                                     decreasing = TRUE), 30), "data.frame")
  fwrite(reglas_soporte_df,
         file.path(ruta_salida, "top_30_reglas_producto_por_soporte.csv"))

  png(file.path(ruta_salida, "reglas_producto_soporte_lift.png"),
      width = 1400, height = 900, res = 150)
  plot(top_reglas_producto, measure = c("support", "lift"),
       shading = "confidence",
       main = "Reglas producto-producto: soporte y lift")
  dev.off()
}

# Como leer una regla exportada, por ejemplo {A} => {B}:
# support = P(A interseccion B)
# confidence = P(B dado A)
# lift = P(B dado A) / P(B)
# Un lift mayor que 1 indica asociacion positiva; uno cercano a 1 indica que
# B aparece con A aproximadamente lo esperable por la popularidad de B.

# -------------------------
# 8. Repetir a nivel de categoria (pasillo)
# -------------------------
# Una regla de producto puede ser muy especifica. Agrupar en 'aisle' permite
# hallar patrones mas generales y accionables, por ejemplo frutas => yogurt.
categorias_por_orden <- items[
  , .(categorias = list(unique(aisle))),
  by = order_id
]

lista_categorias <- setNames(
  categorias_por_orden$categorias,
  categorias_por_orden$order_id
)
transacciones_categoria <- as(lista_categorias, "transactions")

rules_categoria <- apriori(
  transacciones_categoria,
  parameter = list(
    support = SOPORTE_MINIMO_CATEGORIA,
    confidence = CONFIANZA_MINIMA_CATEGORIA,
    minlen = 2,
    maxlen = 2,
    target = "rules"
  )
)

cat("\nNumero de reglas categoria => categoria:", length(rules_categoria), "\n")

if (length(rules_categoria) > 0) {
  top_reglas_categoria <- head(sort(rules_categoria, by = "lift",
                                    decreasing = TRUE), 30)
  inspect(top_reglas_categoria)
  fwrite(as(top_reglas_categoria, "data.frame"),
         file.path(ruta_salida, "top_30_reglas_categoria_por_lift.csv"))
}

# -------------------------
# 9. Extension: patron por hora del dia
# -------------------------
# La pregunta correcta no es solo P(A interseccion B interseccion hora), sino
# si la relacion cambia al condicionar por hora:
# P(B dado A, hora) frente a P(B dado hora).
# A continuacion se deja una tabla de apoyo para escoger horas a analizar.
items_hora <- merge(
  items,
  orders[, .(order_id, order_hour_of_day)],
  by = "order_id",
  all.x = TRUE
)

ordenes_por_hora <- unique(items_hora[, .(order_id, order_hour_of_day)])[
  , .N, by = order_hour_of_day
][order(order_hour_of_day)]
fwrite(ordenes_por_hora, file.path(ruta_salida, "ordenes_por_hora.csv"))

# Proximo paso sugerido:
# filtrar items_hora[order_hour_of_day %in% c(18, 19, 20)] y repetir desde
# la seccion 5. Asi se comparan reglas nocturnas contra las reglas globales.

# -------------------------
# 10. Cierre
# -------------------------
cat("\nProceso terminado. Revise la carpeta:\n", ruta_salida, "\n")
cat("La siguiente etapa sera evaluar reglas/recomendaciones contra train.\n")
