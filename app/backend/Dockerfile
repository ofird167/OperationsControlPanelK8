FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy application configuration
COPY package.json ./

# Install only production dependencies
RUN npm install --only=production

# Copy source code
COPY server.js ./

# Set environment defaults
ENV PORT=5000
EXPOSE 5000

# Start server
CMD ["node", "server.js"]
