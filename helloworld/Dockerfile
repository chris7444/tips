#
# simple hellow world node.js app
#
#  see https://nodejs.org/en/docs/guides/nodejs-docker-webapp/
#
FROM node:alpine
# Create app directory
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app
COPY package.json /usr/src/app/
RUN npm install
COPY . /usr/src/app
EXPOSE 8080
CMD [ "npm", "start" ]
