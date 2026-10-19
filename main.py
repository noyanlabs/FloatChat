import xarray as xr
from sqlalchemy import create_engine

ds = xr.open_dataset("20210101_prof.nc")
df = ds[["N_PROF", "N_LEVELS", "TEMP", "PRES", "PSAL", "LATITUDE", "LONGITUDE", "JULD", "TEMP_QC", "PRES_QC", "PSAL_QC", "TEMP_ADJUSTED", "PRES_ADJUSTED", "PSAL_ADJUSTED",]].to_dataframe().reset_index()

df = df.dropna(subset=['PRES', 'TEMP', 'PSAL'])
mask = df["TEMP_QC"] > b'2'
df.loc[mask, "TEMP"] = df.loc[mask, "TEMP_ADJUSTED"]
mask = df["PRES_QC"] > b'2'
df.loc[mask, "PRES"] = df.loc[mask, "PRES_ADJUSTED"]
mask = df["PSAL_QC"] > b'2'
df.loc[mask, "PSAL"] = df.loc[mask, "PSAL_ADJUSTED"]

engine = create_engine("postgresql://neondb_owner:npg_SPc8ERGTKbg1@ep-tiny-pine-azinpnj0-pooler.c-3.ap-southeast-1.aws.neon.tech/floatchat?sslmode=require&channel_binding=require")
df.to_sql('profiles', engine, if_exists='append', index=False)


# df.to_excel("20210101_prof.xlsx")