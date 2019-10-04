#!/bin/bash

#1st check if a new .jar befoe create new container
#Assuming that the script argument is put in a form "dir/jar_file"

Work_dir=$(echo $1 | cut -d/ -f1 ) 
echo $Work_dir
Current_jar=$(grep "ENV" $Work_dir/Dockerfile | awk '{print $3}')
echo $Current_jar
new_jar=$(echo $1 | cut -d/ -f2 )
echo $new_jar
if [ "$Current_jar" == "$new_jar" ]; 
then
	echo "u r in"
else
  sed -i "s/$Current_jar/$new_jar/g" ./$Work_dir/Dockerfile
  echo "jar file has been updated"
  echo "App container will be updated"

## Get Container Name & Version
  DesiredApp=$(echo $Work_dir|cut -c1-7)
  cont=$(docker ps -f name=$DesiredApp -q) 
  cont_f_name=$(docker inspect "$cont" -f "{{ .Name }}"|cut -d/ -f2)
  cont_name=$(docker inspect "$cont" -f "{{ .Name }}"|cut -d/ -f2|cut -d "." -f1)
  cont_version=$(docker inspect "$cont" -f "{{ .Name }}"|cut -d/ -f2|cut -d "." -f2)
  cont_ver_num=$(echo $cont_version|cut -c2)
  echo "Current runnign cont is: $cont_f_name"

## Get Image Name & Version
  Cur_img=$(docker inspect $cont_f_name -f "{{.Config.Image}}")
  image_name=$(docker inspect $cont_f_name -f "{{.Config.Image}}"|cut -d: -f1)
  image_ver=$(docker inspect $cont_f_name -f "{{.Config.Image}}"|cut -d: -f2)  
  img_ver_num=$(echo $image_ver|cut -c2)
  echo $img_ver_num

  #cp docker-compose_v1.yml docker-compose_v$(($version_num+1)).yml
   #sed -i "s/$image_name:$image_ver/$image_name:"

## Get container network
  cont_net=$(docker inspect $cont_f_name -f "{{json .NetworkSettings.Networks }}"|cut -d '"' -f2)

### Build the new container using new compose
   cat > $cont_name.v$(($cont_ver_num+1))-compose.yml <<EOF

version: '3'
services:
    $cont_name.v$(($cont_ver_num+1)):
         build: ./$Work_dir
         image: $image_name:v$(($img_ver_num+1))
         container_name: $cont_name.v$(($cont_ver_num+1))
         networks:
             - $cont_net
networks:
  $cont_net:
    external: true

EOF
  
### Run new container
  if [[ `docker-compose -f $cont_name.v$(($cont_ver_num+1))-compose.yml up -d` ]]; then
	  echo "Starting $cont_name-v$(($cont_ver_num+1)) ..."
          sleep 20s

## Editing nginx configuration to redirect the requests to the new container ...
          sed -i "s/$cont_f_name:8080/$cont_name.v$(($cont_ver_num+1)):8080/g" ./proxy/nginx.conf
          docker exec -i nginxproxy sed -i "s/$cont_f_name:8080/$cont_name.v$(($cont_ver_num+1)):8080/g" /etc/nginx/nginx.conf

## Restart the nginx service to redirect the request to the new container.
          docker restart nginxproxy 
 
## Remove old container
          docker stop $cont_f_name && docker rm $cont_f_name

## Update the current compose file to update all the stack
          sed -i "s/$cont_f_name/$cont_name.v$(($cont_ver_num+1))/g" docker-compose.yml
	  sed -i "s/$Cur_img/$image_name:v$(($img_ver_num+1))/g" docker-compose.yml
	  rm -f $cont_name.v$(($cont_ver_num+1))-compose.yml
  fi

fi