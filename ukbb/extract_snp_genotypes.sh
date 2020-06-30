# Get imputed SNP genotypes
plink2 \
  --bgen /data1/deep_storage/ukbiobank/imp_bgen_files/ukb_imp_chr9_v3.bgen ref-first \
  --sample /data1/deep_storage/ukbiobank/genotypes/ukb41039_imp_chr9_v3_s487320.sample \
  --mind 0.01 \
  --extract snps.txt \
  --export A \
  --out imputed_genotypes

# Get information about the variants (ref/alt/position/etc.)
sqlite3 \
  -header \
  -csv /data1/deep_storage/ukbiobank/imp_bgi_files/004_ukb_imp_chr9_v3.bgen.bgi \
  "SELECT * FROM Variant WHERE rsid IN ('rs8176746', 'rs8176719')" > \
  imputed_variant_info.csv

# Extract allele frequencies (to double check that we have variant direction correct (G > C))
plink2 \
  --bgen /data1/deep_storage/ukbiobank/imp_bgen_files/ukb_imp_chr9_v3.bgen ref-first \
  --sample /data1/deep_storage/ukbiobank/genotypes/ukb41039_imp_chr9_v3_s487320.sample \
  --extract /data1/home/mnz2108/git/abo_covid_analysis/ukbb/snps.txt \
  --freq \
  --out /data1/home/mnz2108/git/abo_covid_analysis/ukbb/imputed_variants
