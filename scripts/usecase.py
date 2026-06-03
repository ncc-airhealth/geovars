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
        # .calc(group="coordinate", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="distance_to_airport", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="distance_to_road", year=[2005, 2010, 2015, 2020])
        # .calc(group="distance_to_railway", year=[2005, 2010, 2015, 2020])
        # .calc(group="distance_to_railstation", year=[2005, 2010, 2015, 2020])
        # .calc(group="distance_to_bus_stop", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="distance_to_coast", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="distance_to_river", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="distance_to_mdl", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="distance_to_port", year=[2000, 2005, 2010, 2015, 2020])
        # .calc(group="car_registration", year=[2000, 2005, 2010, 2015, 2020])
        # .test_calc(group="ndvi_statistics", year=[2000, 2005, 2010, 2015, 2020], buffer=[1000, 5000])
        # .test_calc(group="road_llw", year=[2005, 2010, 2015, 2020], buffer=[25, 50, 100, 300, 500, 1000, 5000])
        # .calc(group="sgis_statistics", year=[2000, 2005, 2010, 2015, 2020], buffer=[100, 300, 1000, 5000])
        # .safe_calc(group="landcover", year=[2000, 2005, 2010, 2015, 2020], buffer=[100, 300, 1000, 5000])
        # .calc(group="emission", year=[2000, 2005, 2010, 2015, 2020], buffer=[3000, 10000, 20000])
        .test_calc(group="elevation", year=[2000, 2005, 2010, 2015, 2020], rel_height=[20 ,50], buffer=[1000, 5000])
        
        
        
        
        .df(as_wide=True)
    )

    # verbose
    print(gv_df)




if __name__ == "__main__":
    main()