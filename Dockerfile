FROM node:22-alpine
WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci --only=production
COPY src/ .
USER node
EXPOSE 8080
CMD ["node", "server.js"]
