FROM nginx

COPY ./dist/ /usr/share/nginx/html

COPY ./vhost.nginx.conf /etc/nginx/conf.d/file-upload.conf

EXPOSE 80