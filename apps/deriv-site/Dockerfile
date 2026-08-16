FROM nginx@sha256:1a8724a52d432501548a8d8681bb1554c2d09778f8b9ed0882fc3442549980b7

COPY nginx.conf /etc/nginx/nginx.conf
COPY public/ /usr/share/nginx/html/

RUN chown -R nginx:nginx /usr/share/nginx/html \
  && find /usr/share/nginx/html -type d -exec chmod 0555 {} \; \
  && find /usr/share/nginx/html -type f -exec chmod 0444 {} \;

USER nginx:nginx
EXPOSE 8080

HEALTHCHECK --interval=20s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
