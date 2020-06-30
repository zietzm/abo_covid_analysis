#!/bin/bash

for i in $(seq 1 22);
do
  plink \
    --memory 20000 \
    --bfile /data1/deep_storage/ukbiobank/pt2281/pfiles_wb/chr_bed_files/chr${i} \
    --maf 0.05 \
    --geno 0.01 \
    --indep-pairwise 1000 kb 1 0.2 \
    --make-bed \
    --out /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/chr${i}

  # Add the file name to a running list (for easier merging below)
  printf "/data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/chr%s\n" $i >> /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/ukb_merged_list.txt
done

# Merge the files
plink \
  --memory 20000 \
  --merge-list /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/ukb_merged_list.txt \
  --remove /data1/deep_storage/ukbiobank/withdraw41039_20181016.csv \
  --make-bed \
  --out /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged

# Remove the chromosome-specific files (no longer needed)
# rm /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/chr*

# Convert to Plink 2 for faster PCA (and other, later operations)
plink2 \
  --memory 20000 \
  --bfile /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged \
  --make-pgen \
  --out /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged

# Compute PCs
plink2 \
  --memory 20000 \
  --pfile /data1/home/mnz2108/data/ukbiobank/genotypes_for_pca/merged \
  --pca approx \
  --out /data1/home/mnz2108/data/ukbiobank/pca/pca
