# Zero-dependency Node.js image (no npm install step needed)
FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json ./
COPY server ./server
COPY scripts ./scripts
COPY docs ./docs
COPY public ./public
COPY data ./data
RUN mkdir -p logs backups && chown -R node:node /app
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1
CMD ["node", "server/index.js"]
