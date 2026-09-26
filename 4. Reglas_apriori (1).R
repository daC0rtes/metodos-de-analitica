if (!require('readxl')) install.packages('readxl')
if (!require('gmodels')) install.packages('gmodels')
if (!require('arules')) install.packages('arules')
if (!require('arulesViz')) install.packages('arulesViz')
if (!require('vcd')) install.packages('vcd')
if (!require('tidyverse')) install.packages('tidyverse')

# Lectura de los datos que deben estar en la ruta que genera el siguiente c?digo
getwd()
cosmetics3 <- read_excel("cosmeticspan.xlsx")
class(cosmetics3)
cosmetics3 %>% View()

# conversi?n a matriz
cosmetics4 <- as.matrix(cosmetics3)
# convertir en transaction
cosmetics4 <- as(cosmetics4,"transactions")
class(cosmetics4)

cosmetics4 %>% View()

itemFrequencyPlot(cosmetics4, topN=15, 
                  cex.names=.7, ylim=c(0,0.6), ylab="Frecuencia de compra relativa")


#obtener una tabla de contingencia
crosst <- CrossTable(cosmetics3$Cosmetiquera, cosmetics3$Rubor, 
                     chisq = TRUE)
crosst

#graficar el resultado
mosaic(~Cosmetiquera + Rubor ,data=cosmetics3, 
       legend=TRUE, shade=TRUE)

##valores observados
crosst$chisq.corr$observed
crosst$prop.tbl

##valores esperados
crosst$chisq.corr$expected

(22+32)*(331+32)/1000
615+331+22+32
## Lift
lift <- 32/19.6
lift

## Reglas
rules <- apriori(cosmetics4,
                 parameter=list(support=0.1,confidence=0.6))

summary(rules)
inspect(head(sort(rules,by="lift"),20))

## Gr?fico
plot(rules, measure = c("support","lift"), 
     shading = "confidence")

## Gr?fico interactivo
plot(rules, measure = c("support","lift"),
     shading = "confidence", control = list(main = "Reglas de MBA"), 
     engine = 'interactive')

## Con confidence mayor a 0.7

subrules <- subset(rules,quality(rules)$confidence>0.7)
plot(subrules, method="matrix", measure="lift",
      control=list(reorder='support/confidence'))

## Grafos

subrules2 <- head(sort(rules, by="lift"), 10)
plot(subrules2, method="graph", arrowSize=0.5)

# Reglas bajando soporte pero limitando la longitud
rules2 <- apriori(cosmetics4,
                  parameter=list(support=0.01,confidence=0.7, 
                                 maxlen=3))
inspect(head(sort(rules2,
                  decreasing = FALSE, by="support"),20))


## Escribir las reglas
write(rules,file="rules.csv",sep=";",dec=",")


