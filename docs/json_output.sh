#!/bin/sh

for what in globals music zones zone queue none all
do
    wget -q -O -  "http://localhost:9999/api?what=${what}&zone=Kitchen"
done