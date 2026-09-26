if (!require('recommenderlab')) install.packages('recommenderlab')
if (!require('devtools')) install.packages('devtools')

data("MovieLense")
#Data MovieLense es un dataset de 100000 ratings de 1664 películas recogidos de 943 usuarios
#a través del sitio web MovieLense entre sept de 1997 y abril de 1998.

class(MovieLense)

#Convertir a matriz para ver los valores
m <- as(MovieLense,"matrix")
dim(m)

#Seleccionamos solo los usuarios con más de 100 ratings
MovieLense100 <- MovieLense[rowCounts(MovieLense)>100]
MovieLense100

#Convertir a matriz para ver los valores
m100 <- as(MovieLense100,"matrix")
dim(m100)

#Armamos el conjunto de entrenamiento con los primeros 50 usuarios
train <- MovieLense100[1:50]
recomen <- Recommender(train,method="UBCF")
recomen

#Matriz de recomendación
datosrecomen <- as(recomen@model$data,"matrix")

#Creación de las N-top recomendaciones para el usuario de la fila 11 del training set
pre11 <- predict(recomen, train[11],n=10)
pre11

pre11list <- as(pre11,"list")
pre11list

mattrain <- as(train[11,c("Apostle, The (1997)", "Shallow Grave (1994)")],"matrix")
mattrain

#Predicción de ratings
pre11rat <- predict(recomen,train[11],type="ratings")
pre11ratmat <- as(pre11rat,"matrix")

#veamos el máximo rating pronosticado
max(pre11ratmat,na.rm = TRUE)

#Y el rating para la primer película recomendada
pre11ratmat[,"Apostle, The (1997)"]

#para nuevos usuarios
prenue <- predict(recomen, MovieLense100[101:102],n=10)
prenue

as(prenue,"list")

