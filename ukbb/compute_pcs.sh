#!/bin/bash

set -e

rm -f /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/ukb_merged_list.txt

# Add the file name to a running list (for easier merging below)
for i in $(seq 1 22);
do
  printf "/data1/deep_storage/ukbiobank/pt2281/pfiles_wb/chr_bed_files/chr${i}\n" $i >> /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/ukb_merged_list.txt
done

# Merge the files
plink \
  --memory 20000 \
  --merge-list /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/ukb_merged_list.txt \
  --remove /data1/deep_storage/ukbiobank/withdraw41039_20181016.csv \
  --make-bed \
  --out /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged

plink \
    --memory 20000 \
    --bfile /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged \
    --maf 0.05 \
    --geno 0.01 \
    --indep-pairwise 1000 kb 1 0.2 \
    --make-bed \
    --out /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged_filtered

# Remove the chromosome-specific files (no longer needed)
rm /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged.*

# Convert to Plink 2 for faster PCA (and other, later operations)
plink2 \
  --memory 20000 \
  --bfile /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged_filtered \
  --make-pgen \
  --out /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged_filtered

# Compute PCs
plink2 \
  --memory 20000 \
  --pfile /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged_filtered \
  --pca approx \
  --out /data1/home/mnz2108/data/ukbiobank/pca/pca
