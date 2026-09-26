# Métodos de Analítica: Sistemas de Recomendación

Proyecto para el Taller grupal 1, basado en las transacciones de Instacart. El propósito no es solo ejecutar un algoritmo: es entender cómo convertir compras reales en recomendaciones y decisiones de negocio.

## Objetivos

- Identificar qué productos o categorías aparecen juntos en una misma canasta de compra.
- Estimar la probabilidad de recomendar un producto B cuando el cliente ya escogió A: $P(B \mid A)$.
- Traducir los patrones encontrados en acciones para tienda virtual, tienda física, promociones y combos.
- Comparar reglas n→1: antecedentes de uno, dos y tres elementos que recomiendan un único producto o pasillo.

## Cómo vamos

- Ya entendimos y preparamos la lógica de *Market Basket Analysis*: una orden es una canasta y una regla tiene soporte, confianza y lift.
- En una muestra de 50.000 órdenes, 41.490 (82,98 %) tienen cuatro o más productos; hay base para probar reglas 1→1, 2→1 y 3→1 a nivel de producto.

## Hoja de ruta del taller

Esta lista es nuestro control de avance. La actualizaremos a medida que la evidencia y el código estén listos.

- [x] Entender la estructura de `orders`, `order_products__prior` y los catálogos de productos/pasillos.
- [x] Preparar el script R y transformar órdenes históricas en canastas.
- [x] Medir el tamaño de las canastas de productos en una muestra de 50.000 órdenes.
- [x] Confirmar que el enfoque del profesor es únicamente reglas **n→1**.
- [x] Ajustar el script: conservar reglas 1→1, habilitar 2→1 y 3→1, y excluir 2→2.
- [ ] Ejecutar la medición de **pasillos distintos** por canasta; el número de productos no equivale al número de pasillos.
- [ ] Ejecutar reglas producto→producto y seleccionar las que tengan soporte, confianza y lift interpretables.
- [ ] Ejecutar reglas pasillo→pasillo y comparar su comportamiento con las reglas de producto.
- [ ] Traducir las reglas seleccionadas en recomendaciones para tienda virtual y acciones para tienda física.
- [ ] Analizar hallazgos adicionales: hora, día de la semana y recurrencia de compra.
- [ ] Usar `order_products__train.csv` para validar si las reglas aprendidas con `prior` se sostienen en órdenes futuras.
- [ ] Redactar conclusiones, limitaciones y recomendaciones finales para el taller.

## La pregunta de negocio

Si un cliente agrega leche a su carrito, ¿conviene sugerir cereal? La respuesta no se basa solamente en que ambos productos sean populares. Buscamos evidencia de que, al observar leche, la probabilidad de comprar cereal aumente.

Una regla se escribe así:

$$
\{A\} \rightarrow \{B\}
$$

Se lee: “cuando A aparece en la canasta, B es una recomendación posible”. No afirma que A cause B ni que A se haya comprado antes; es una regla predictiva basada en la canasta observada.

## Métricas que usaremos

Para una regla $A \rightarrow B$:

| Métrica | Fórmula | Interpretación |
|---|---|---|
| Soporte | $P(A \cap B)$ | Proporción de canastas que contienen A y B. |
| Confianza | $P(B \mid A)$ | Entre quienes tienen A, proporción que también tiene B. |
| Lift | $P(B \mid A) / P(B)$ | Cuánto mejora la probabilidad de B al observar A. |

Un lift mayor que 1 indica asociación positiva. Aun así, una regla debe tener soporte suficiente: una asociación hallada en muy pocas canastas no es una recomendación comercial confiable.

## De reglas uno a uno a combinaciones

| Tipo de regla | Ejemplo | Uso posible |
|---|---|---|
| 1→1 | $\{\text{leche}\}\rightarrow\{\text{cereal}\}$ | Recomendación directa en el carrito. |
| 2→1 | $\{\text{leche, cereal}\}\rightarrow\{\text{banano}\}$ | Recomendación contextual. |
| 3→1 | $\{\text{pasta, salsa, queso}\}\rightarrow\{\text{vino}\}$ | Recomendación muy contextual. |

Una canasta debe tener al menos dos elementos para analizar 1→1, tres para 2→1 y cuatro para 3→1. Un elemento puede ser un producto o un pasillo.

## El problema de combinatoria

Las combinaciones son interesantes, pero crecen muy rápido. Con cuatro productos distintos $\{A,B,C,D\}$ y la restricción n→1, se pueden construir 28 reglas dirigidas:

| Tamaño de antecedente | Número de reglas posibles |
|---:|---:|
| 1→1 | 12 |
| 2→1 | 12 |
| 3→1 | 4 |

Una canasta grande produce muchas combinaciones candidatas. Por eso no escogeremos reglas solo porque existan: Apriori descarta primero las combinaciones que no alcanzan un soporte mínimo. Luego revisaremos confianza, lift e interpretación de negocio. La estrategia es comenzar con 1→1, evaluar 2→1 como extensión principal y usar 3→1 solo cuando el volumen de evidencia lo justifique.

## Datos

La base contiene órdenes, productos, pasillos y departamentos de Instacart:

- `orders.csv`: usuario, secuencia de orden, día y hora.
- `order_products__prior.csv`: productos de las órdenes históricas; es la base para construir canastas.
- `order_products__train.csv`: próxima orden de algunos usuarios; se reservará para validar recomendaciones.
- `products.csv`, `aisles.csv` y `departments.csv`: nombres y categorías de los productos.

La fuente no identifica si una compra ocurrió en tienda física o virtual. Por ello, las mismas reglas se traducirán en acciones diferentes para cada canal, pero no afirmaremos que el comportamiento difiera por canal sin datos que lo respalden.

## Código

El flujo está documentado en [`instacart_apriori_paso_a_paso.R`](instacart_apriori_paso_a_paso.R):

1. Lee y prepara los datos.
2. Mide el tamaño de las canastas.
3. Convierte órdenes en transacciones.
4. Mina reglas Apriori por producto y por categoría.
5. Exporta tablas y gráficos a `salida_apriori/`.
6. Deja preparada la comparación de patrones por hora del día.

Los datos fuente, los PDFs de clase y los resultados generados se mantienen fuera del repositorio.
