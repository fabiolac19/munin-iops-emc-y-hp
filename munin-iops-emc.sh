#!/bin/bash
#Inicializo script bash.

# Modo de uso:
# ./munin-iops.sh path_to_directory output

# 1º parte:
# Incluir el directorio donde se encuentran las definiciones de las maquinas virtuales.

#Verifica que el usuario haya ingresado correctamente los parametros de entrada.
#Asigna a variable salida el primer parametro introducido que posee el nombre de archivo de salida. En caso de no existir se crea.
#Si el usuario no ingreso correctamente el modo de uso se  notifica error por pantalla.
if [ $1 ]; then
 	salida=$1
else
	echo "******************************************************************************"
	echo "[ERROR] Ingrese correctamente el nombre del directorio o del archivo de salida"
	echo "******************************************************************************"
 	exit 1
fi

#Crea un directorio temporal directory.
directory=$(mktemp -d)
#Ingresa al mismo 
cd $directory
#Realiza copia del repositorio que posee las definiciones de maquinas virtuales, utilizando comando check-out de subversion.
svn co http://noc-svn.psi.unc.edu.ar/servicios/xen

rm -rf $directory/xen/suspendidos $directory/xen/.svn $directory/xen/old $directory/xen/error $directory/xen/templates

#Crea archivos de texto a utilizar.
> result.txt
> vm.txt
> escrituras.txt
> lecturas.txt
> total_escrituras.txt
> total_lecturas.txt
> total.txt

#Para cada archivo del directorio directory lee linea por linea y hace un echo de cada linea en un archivo vm.txt
for file in $directory/xen/* ; do
 	while read -r line; do
        echo "$line" >> vm.txt
  	done < $file

#Realiza busqueda de las lineas de vm.txt que contengan dev o mapper. Y de estas, que no contengan rogelio|device....
#Las lineas obtenidas las guarda en el archivo parser.txt
	egrep "dev|mapper" vm.txt | egrep -v "rogelio|device|args|description|file|\(name" > parser.txt

#Cuenta las lineas obtenidad en el archivo parser.txt con el comando cat
	i=$(cat parser.txt | wc -l)

#Lee linea por linea con el comando sed el archivo parser.txt. Define variables c y d para lectura de una linea y linea siguiente.
#Las dos lineas conscecutivas se guardan en lineaN0 y lineaN1
	for (( c=1; c<=i; c++ ))
	do
	   lineaN0=$(sed -n -e ${c}p parser.txt)
	   (( d=c+1 ))
	   lineaN1=$(sed -n -e ${d}p parser.txt)
	#   echo "Linea 0: "$lineaN0
	#   echo "Linea 1: "$lineaN1

#Filtramos solo lineas conscecutivas que posean informacion del disco y nombre de maquinas virtuales
#De esta forma verificamos que no sean dos lineas iguales. Por ejemplo dos lineas seguidas con informacion de discos diferentes.
#Realizamos la comparacion cortando los primeros 5 caracteres y comparandolos. Tambien tenemos en cuenta si la linea siguiente es nula.
	   if [[ "$(echo $lineaN0 | cut -c1-5)" = "$(echo $lineaN1 | cut -c1-5)" ||  -z "$lineaN1" ]]; then
		echo "Se repiten o lineaN1 es NULL" > /dev/null

#Si las lineas son distintas se procede a obtener los parametros solicitados. Para ello se emplea el comando sed de la siguiente manera:
#borra -(dev -		: s/(dev //g
#borra parentisis	: s/(//g ;s/)//g
#borra -\:disk - 	: s/\:disk //g; 
#borra uname phy :/dev/mapper : s/uname//g;s/phy\:\/dev\/mapper\///g
#borra todo lo anterior al caracter / : s/.*\///g

#Realiza un echo con nombre del archivo linea, disco y nombre de maquina virtual al archivo result.txt
 	 else
		echo $file $lineaN0 $lineaN1 | sed 's/(dev //g;s/(//g;s/)//g;s/\:disk //g;s/uname//g;s/phy\:\/dev\/mapper\///g;s/.*\///g' >> result.txt
#Salta linea, ya que ya tomo las dos lineas solicitadas
		(( c=c+1 ))
	   fi
	done
> vm.txt
done

# 2º parte
# Definir el formato de los distintos tipos de graficos

#Lee linea por linea el archivo result.txt.
while read -r line; do

#Corta la linea por campos.
#Asigna primer campo con el nombre de la vm a la variable vm, el segundo campo se asigna a la variable disk, y el tercer campo que contiene el nombre del disco de la vm a la variable res
        vm=$(echo $line | cut -f1 -d' ')
        disk=$(echo $line | cut -f2 -d' ')
        res=$(echo $line | cut -f3 -d' ')

#Busca en el archivo de configuracion munin la ruta de ubicacion de la vm.
#Toma una linea y corta todo lo anterior al caracter [ y elimina el caracter ]
        pline=$(echo $(egrep "$vm\.|$vm\]" /etc/munin/munin.conf | head -n1 | sed 's/^.*\[//g;s/\]//g'))
#Verifica que pline no sea nulo
        if [ -z $pline ]; then
                echo $pline > /dev/null
        else

#Conforma los archivos con lecturas, escrituras, total, de forma que munin los entienda para graficar.
                #Escrituras
                # echo "****************************************************"
                echo "$res=$pline:diskstats_iops.$disk.wrio" >> escrituras.txt
                #Lecturas
                # echo "****************************************************"
                echo "$res=$pline:diskstats_iops.$disk.rdio" >> lecturas.txt
                #Total Escrituras
                # echo "****************************************************"
                echo "$pline:diskstats_iops.$disk.wrio" >> total_escrituras.txt
                #Total Lecturas
                # echo "****************************************************"
                echo "$pline:diskstats_iops.$disk.rdio" >> total_lecturas.txt
                #Total
                # echo "****************************************************"
                echo "$pline:diskstats_iops.$disk.wrio" >> total.txt
                echo "$pline:diskstats_iops.$disk.rdio" >> total.txt
                fi
done < result.txt

# 3º parte
# Completar la estructura del archivo emc
#Borra contenido previo de la variable salida
> $salida

#Inicializa archivo salida con configuraciones de etiqueta y demas, propias de Munin
echo "[UNC;PSI;NOC;Infraestructura;Storage;EMC]"			>> $salida
echo "    update no"							>> $salida
echo "    diskstats_iops.update no"					>> $salida
echo "    diskstats_iops.graph_title IOPS Lecturas"			>> $salida
echo "    diskstats_iops.graph_category IOPS"				>> $salida
echo "    diskstats_iops.graph_args --base 1000"			>> $salida
echo "    diskstats_iops.graph_vlabel IOs/sec"				>> $salida
echo "    diskstats_iops.graph_order \\"				>> $salida

#Lee linea por linea y va escribiendo en salida el archivo lecturas.txt
while read -r line; do
        echo "          $line \\"					>> $salida
done < lecturas.txt
# Quitar el caracter "\" de la ultima linea
        line=$(tail -n1 $salida | sed 's/\\//g')
        sed '$ d' $salida                                               > temp.txt
        cat temp.txt                                                    >  $salida
        echo "$line"                                                    >> $salida
echo " "								>> $salida
echo "    diskstats_iops_1.update no"					>> $salida
echo "    diskstats_iops_1.graph_title IOPS Escrituras"			>> $salida
echo "    diskstats_iops_1.graph_category IOPS"				>> $salida
echo "    diskstats_iops_1.graph_args --base 1000"			>> $salida
echo "    diskstats_iops_1.graph_vlabel IOs/sec"			>> $salida
echo "    diskstats_iops_1.graph_order \\"				>> $salida

#Lee linea por linea y va escribiendo en salida el archivo escrituras.txt
while read -r line; do
        echo "          $line \\"					>> $salida
done < escrituras.txt
        line=$(tail -n1 $salida | sed 's/\\//g')
        sed '$ d' $salida                                               > temp.txt
        cat temp.txt                                                    >  $salida
        echo "$line"                                                    >> $salida
echo " "								>> $salida
echo "    diskstats_iops_2.update no"					>> $salida
echo "    diskstats_iops_2.graph_title IOPS Lecturas Total"		>> $salida
echo "    diskstats_iops_2.graph_category IOPS"				>> $salida
echo "    diskstats_iops_2.graph_args --base 1000"			>> $salida
echo "    diskstats_iops_2.graph_vlabel IOs/sec"			>> $salida
echo "    diskstats_iops_2.total_iops_1.label IOPS Lecturas Total"	>> $salida
echo "    diskstats_iops_2.total_iops_1.sum \\"				>> $salida

#Lee linea por linea y va escribiendo en salida el archivo total_lecturas.txt
while read -r line; do
        echo "          $line \\"					>> $salida
done < total_lecturas.txt
        line=$(tail -n1 $salida | sed 's/\\//g')
        sed '$ d' $salida                                               > temp.txt
        cat temp.txt                                                    >  $salida
        echo "$line"                                                    >> $salida
echo " "								>> $salida
echo "    diskstats_iops_3.update no"					>> $salida
echo "    diskstats_iops_3.graph_title IOPS Escrituras Total"		>> $salida
echo "    diskstats_iops_3.graph_category IOPS"				>> $salida
echo "    diskstats_iops_3.graph_args --base 1000"			>> $salida
echo "    diskstats_iops_3.graph_vlabel IOs/sec"			>> $salida
echo "    diskstats_iops_3.total_iops_2.label IOPS Escrituras Total"	>> $salida
echo "    diskstats_iops_3.total_iops_2.sum \\"				>> $salida

#Lee linea por linea y va escribiendo en salida el archivo total_escrituras.txt
while read -r line; do
        echo "          $line \\"					>> $salida
done < total_escrituras.txt
	line=$(tail -n1 $salida | sed 's/\\//g')
	sed '$ d' $salida						> temp.txt
	cat temp.txt							>  $salida
	echo "$line"							>> $salida				
echo " "								>> $salida
echo "    diskstats_iops_4.update no"					>> $salida
echo "    diskstats_iops_4.graph_title IOPS Total"			>> $salida
echo "    diskstats_iops_4.graph_category IOPS"				>> $salida
echo "    diskstats_iops_4.graph_args --base 1000"			>> $salida
echo "    diskstats_iops_4.graph_vlabel IOs/sec"			>> $salida
echo "    diskstats_iops_4.total_iops_3.label IOPS Total"		>> $salida
echo "    diskstats_iops_4.total_iops_3.sum \\"				>> $salida

#Lee linea por linea y va escribiendo en salida el archivo total.txt
while read -r line; do
        echo "          $line \\"					>> $salida
done < total.txt
        line=$(tail -n1 $salida | sed 's/\\//g')
        sed '$ d' $salida                                               > temp.txt
        cat temp.txt                                                    >  $salida
        echo "$line"                                                    >> $salida
echo " "								>> $salida

# Cargamos el munin-conf.d con salida
mv $salida /etc/munin/munin-conf.d/$salida
# Borramos archivos temporales
rm -rf $directory
