FROM nginx:1.27-alpine
LABEL org.opencontainers.image.title="FoodWastePortal" \
      org.opencontainers.image.description="Surplus food tracking and redistribution demo"
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
