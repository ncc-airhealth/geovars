import duckdb
import geovars as gv

DB_PATH = "/Users/hus/Library/CloudStorage/Dropbox/패밀리룸/data-pipeline-stac/_data/geovariable-database/version=3.0.1/geovariable-database.db"
POINT_PATH = "/Users/hus/Library/CloudStorage/Dropbox/패밀리룸/data-pipeline-stac/_data/geovariable-reference-point/version=3.0.1/assets/geovariable-reference-point-all.parquet"
YEARS = [2000, 2005, 2010, 2015, 2020]

def main():

    # prepare
    input_df = duckdb.read_parquet(POINT_PATH)
    calculator = gv.Calculator(
        database=DB_PATH, 
        memory_limit="8GB", 
        workers=8,
    )

    # calculate
    gv_df = (
        calculator
        .set_input(tbl=input_df, pk="pid", x="longitude", y="latitude", crs="EPSG:4326")
        .cluster(algorithm="hilbert", size=500)
        .calc(group="coordinate", year=YEARS)
        .calc(group="bus_distance", year=YEARS)
        # .safe_calc(group="road_distance", year=YEARS)
        # .safe_calc(group="road_llw")
        .df(as_wide=True)
    )

    # verbose
    print(gv_df)




if __name__ == "__main__":
    main()