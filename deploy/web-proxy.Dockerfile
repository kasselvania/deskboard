FROM node:24.19.0-bookworm-slim@sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03 AS build

WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
COPY packages/contracts/package.json packages/contracts/package.json
RUN npm ci

COPY tsconfig.json tsconfig.tools.json ./
COPY packages/contracts packages/contracts
COPY apps/web apps/web

RUN npm run build --workspace @deskboard/contracts \
    && npm run build --workspace @deskboard/web

FROM nginx:1.28.3-alpine@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236 AS runtime

RUN rm -f /etc/nginx/conf.d/default.conf

COPY deploy/private-proxy.conf /etc/nginx/nginx.conf
COPY --from=build --chown=nginx:nginx /app/apps/web/dist /usr/share/nginx/html

USER nginx
EXPOSE 8080
STOPSIGNAL SIGQUIT

ENTRYPOINT []
CMD ["nginx", "-g", "daemon off;"]
