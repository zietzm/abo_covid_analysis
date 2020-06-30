# # Get genotyped SNP genotypes
# plink \
#   --bfile /data1/deep_storage/ukbiobank/pt2281/pfiles_wb/chr_bed_files/chr9 \
#   --mind 0.01 \
#   --extract /data1/home/mnz2108/git/abo_covid_analysis/ukbb/snps.txt \
#   --recode A \
#   --out genotyped_genotypes

# # Get information about the variants (ref/alt/position/etc.)
# plink \
#   --bfile /data1/deep_storage/ukbiobank/pt2281/pfiles_wb/chr_bed_files/chr9 \
#   --extract /data1/home/mnz2108/git/abo_covid_analysis/ukbb/snps.txt \
#   --make-just-bim \
#   --out genotyped_genotypes

# Get genotyped SNP genotypes
plink \
  --bed /data1/deep_storage/ukbiobank/bed_files/ukb_cal_chr9_v2.bed \
  --bim /data1/home/mnz2108/data/ukbiobank/bim/ukb_snp_chr9_v2.bim \
  --fam /data1/deep_storage/ukbiobank/genotypes/ukb41039_cal_chr9_v2_s488288.fam \
  --mind 0.01 \
  --extract /data1/home/mnz2108/git/abo_covid_analysis/ukbb/snps.txt \
  --recode A \
  --out genotyped_genotypes

# Get information about the variants (ref/alt/position/etc.)
plink \
  --bed /data1/deep_storage/ukbiobank/bed_files/ukb_cal_chr9_v2.bed \
  --bim /data1/home/mnz2108/data/ukbiobank/bim/ukb_snp_chr9_v2.bim \
  --fam /data1/deep_storage/ukbiobank/genotypes/ukb41039_cal_chr9_v2_s488288.fam \
  --extract /data1/home/mnz2108/git/abo_covid_analysis/ukbb/snps.txt \
  --make-just-bim \
  --out genotyped_genotypes

# # Get imputed SNP genotypes
# plink2 \
#   --bgen /data1/deep_storage/ukbiobank/imp_bgen_files/ukb_imp_chr9_v3.bgen ref-first \
#   --sample /data1/deep_storage/ukbiobank/genotypes/ukb41039_imp_chr9_v3_s487320.sample \
#   --mind 0.01 \
#   --extract snps.txt \
#   --export A \
#   --out imputed_genotypes

# # Get information about the variants (ref/alt/position/etc.)
# sqlite3 \
#   -header \
#   -csv /data1/deep_storage/ukbiobank/imp_bgi_files/004_ukb_imp_chr9_v3.bgen.bgi \
#   "SELECT * FROM Variant WHERE rsid IN ('rs8176746', 'rs8176719', 'rs687289', 'rs8176747', 'rs41302905')" > \
#   imputed_variant_info.csv

# # Extract allele frequencies (to double check that we have variant direction correct (G > C))
# plink2 \
#   --bgen /data1/deep_storage/ukbiobank/imp_bgen_files/ukb_imp_chr9_v3.bgen ref-first \
#   --sample /data1/deep_storage/ukbiobank/genotypes/ukb41039_imp_chr9_v3_s487320.sample \
#   --extract /data1/home/mnz2108/git/abo_covid_analysis/ukbb/snps.txt \
#   --freq \
#   --out /data1/home/mnz2108/git/abo_covid_analysis/ukbb/imputed_variants


