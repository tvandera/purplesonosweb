# Use the official Perl image
FROM perl:latest

# Install Carton and build tools
RUN cpanm --notest Carton && \
    apt-get update && \
    apt-get install -y build-essential libgd-dev

# Set working directory
WORKDIR /app

# Copy cpanfile and install dependencies
COPY cpanfile /app/
RUN carton install

# Copy the rest of your application
COPY . /app/

# Optional: use carton for running your app
# ENTRYPOINT ["carton", "exec", "--"]
# CMD ["perl", "your-script.pl"]

# Or just run perl directly (useful if your code doesn't depend heavily on Carton)
# CMD ["perl", "your-script.pl"]

