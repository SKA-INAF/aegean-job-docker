#!/usr/bin/env python3

##################################################
###          MODULE IMPORT
##################################################
## STANDARD MODULES
import os
import sys
import subprocess
import string
import time
import signal
from threading import Thread
import datetime
import numpy as np
import random
import math
import json

## COMMAND-LINE ARG MODULES
import getopt
import argparse
import collections

## ASTRO
from astropy.table import Table
from astropy.coordinates import SkyCoord
from astropy import units as u

## LOGGER
import logging
import logging.config
logger = logging.getLogger(__name__)
logging.basicConfig(format="%(asctime)-15s %(levelname)s - %(message)s",datefmt='%Y-%m-%d %H:%M:%S')
logger= logging.getLogger(__name__)
logger.setLevel(logging.INFO)

###########################
##     ARGS
###########################
def get_args():
	"""This function parses and return arguments passed in"""
	parser = argparse.ArgumentParser(description="Parse args.")

	parser.add_argument('-inputfile_island','--inputfile_island', dest='inputfile_island', required=True, type=str, default='', help='Input ascii island catalog (.tab)') 
	parser.add_argument('-inputfile_comp','--inputfile_comp', dest='inputfile_comp', required=True, type=str, default='', help='Input ascii component catalog (.tab)') 
	parser.add_argument('-outfile','--outfile', dest='outfile', required=False, type=str, default='', help='Output json filename with island+components catalog') 
	args = parser.parse_args()	

	return args

#################
##   HELPERS   ##
#################
def get_iau_name(ra_str, dec_str):
	""" Convert ra/dec string to IAU identifier"""
	#print("pto 1")
	coord = SkyCoord(ra=ra_str, dec=dec_str, unit=(u.hourangle, u.deg), frame='fk5')
	#print("pto 2")
	ra = coord.ra.to_string(unit=u.hour, sep='', pad=True, precision=2)
	dec = coord.dec.to_string(sep='', pad=True, alwayssign=True, precision=1)
	return f"J{ra}{dec}"
    

def make_island_json_catalog(t_island, t_comp):
	""" Convert input Aegean island ascii catalog to json format (similar to Caesar format) """

	# - Init out dict
	d= {
		"metadata": {},
		"sources": []
	}
	
	# - Create island/comp maps
	logger.info("Creating island map ...")
	island_dict= {}
	for item in t_island:
		island_index= item["island"]
		island_dict[island_index]= {
			"island": item,
			"components": []
		}

	logger.info("Adding components to island map ...")
	for item in t_comp:
		island_index= item["island"]
		island_dict[island_index]["components"].append(item)


	# - Fill output dict
	logger.info("Filling output dict ...")
	for key, value in island_dict.items():
		island_index= key
		item= value["island"]
		comp_list= value["components"]
		
		uuid= item["uuid"]
		sname= "S" + str(island_index)
		ra_str= item["ra_str"]
		dec_str= item["dec_str"] 
		
		#logger.debug(f"get_iau_name for island {island_index} (ra_str={ra_str}, dec_str={dec_str}) ...")
		iau_name= get_iau_name(ra_str, dec_str)
		
		# - Fill source dict
		sdict= {}
		sdict["name"]= sname
		#sdict["x0"]= -999 # NOT AVAILABLE
		#sdict["y0"]= -999 # NOT AVAILABLE
		sdict["ra"]= float(item["ra"])
		sdict["dec"]= float(item["dec"])
		sdict["ra_str"]= item["ra_str"]
		sdict["dec_str"]= item["dec_str"]
		#sdict["class_label"]= "UNKNOWN"       # NOT AVAILABLE
		#sdict["class_score"]= -1              # NOT AVAILABLE      
		#sdict["morph_label"]= "UNKNOWN"       # NOT AVAILABLE
		#sdict["sourceness_label"]= "UNKNOWN"  # NOT AVAILABLE
		#sdict["sourceness_score"]= -1         # NOT AVAILABLE
		sdict["nest_level"]= 0               
		#sdict["tags"]= []                     # NOT AVAILABLE  
		sdict["nislands"]= 1
		sdict["islands"]= []
	
		# - Fill island dict
		idict= {}
		idict["name"]= str(sname)
		idict["iau_name"]= str(iau_name)
		idict["uuid"]= str(item["uuid"])
		idict["npix"]= int(item["pixels"])
		#idict["x"]= -999 # NOT AVAILABLE
		#idict["y"]= -999 # NOT AVAILABLE
		idict["ra"]= float(item["ra"])
		idict["dec"]= float(item["dec"])
		idict["x_width"]= float(item["x_width"])
		idict["y_width"]= float(item["y_width"])
		idict["max_angular_size"]= float(item["max_angular_size"])
		idict["pa"]= float(item["pa"])
		idict["beam_area"]= float(item["beam_area"])
		#idict["xmin"]= -999 # NOT AVAILABLE
		#idict["xmax"]= -999 # NOT AVAILABLE
		#idict["ymin"]= -999 # NOT AVAILABLE
		#idict["ymax"]= -999 # NOT AVAILABLE
		#idict["ra_min"]= -999 # NOT AVAILABLE
		#idict["ra_max"]= -999# NOT AVAILABLE
		#idict["dec_min"]= -999 # NOT AVAILABLE
		#idict["dec_max"]= -999 # NOT AVAILABLE	
		#idict["vertices"]= -999 # NOT AVAILABLE
		#idict["pixels"]= [] # NOT AVAILABLE
		idict["Smax"]= float(item["peak_flux"])
		idict["Stot"]= float(item["int_flux"])
		idict["eta"]= float(item["eta"])
		idict["bkg"]= float(item["background"])
		idict["rms"]= float(item["local_rms"])
		idict["fit_flags"]= str(item["flags"])
		#idict["morph_label"]= "UNKNOWN"      # NOT AVAILABLE	
		#idict["sourceness_label"]= "UNKNOWN" # NOT AVAILABLE	
		#idict["sourceness_score"]= -1        # NOT AVAILABLE	
		#idict["border"]= -1                  # NOT AVAILABLE	
		#idict["class_label"]= "UNKNOWN"      # NOT AVAILABLE	 
		#idict["class_score"]= -1             # NOT AVAILABLE	
		#idict["tags"]= []                    # NOT AVAILABLE	
		#idict["resolved"]= -1                # NOT AVAILABLE	
		#idict["beam_area_ratio_par"]= -1     # NOT AVAILABLE	
		#idict["circ_ratio_par"]= -1          # NOT AVAILABLE	
		#idict["elongation_par"]= -1          # NOT AVAILABLE	
		#idict["min_bbox_par"]= -1            # NOT AVAILABLE	
		#idict["min_size"]= -1                # NOT AVAILABLE	
		#idict["max_size"]= -1                # NOT AVAILABLE	
		#idict["crossmatch_info"]= []         # NOT AVAILABLE	
		#idict["spectral_info"]= []           # NOT AVAILABLE	
		idict["fit_info"]= {
			"ncomponents": int(item["components"]),
			"model": "gaus",
			"ndata": int(item["pixels"]),
			#"npars": -999, # NOT AVAILABLE
			#"npars_free": -999, # NOT AVAILABLE
			#"chi2": -999, # NOT AVAILABLE
			#"ndf": -999, # NOT AVAILABLE
			#"cov_matrix": [], # NOT AVAILABLE
			#"fit_quality": -999, # NOT AVAILABLE
			#"flux": -999, , # NOT AVAILABLE
			#"flux_err": -999, , # NOT AVAILABLE
			"components": []
		}
			
		# - Fill component dict
		for item_comp in comp_list:
			iau_name= get_iau_name(item_comp["ra_str"], item_comp["dec_str"])
			
			d_comp= {}
			d_comp["iau_name"]= str(iau_name)
			d_comp["uuid"]= str(item_comp["uuid"])
			#d_comp["x"]= -999 # NOT AVAILABLE
			#d_comp["y"]= -999 # NOT AVAILABLE
			#d_comp["x_err"]= -999 # NOT AVAILABLE
			#d_comp["y_err"]= -999 # NOT AVAILABLE
			d_comp["ra"]= float(item_comp["ra"])
			d_comp["dec"]= float(item_comp["dec"])
			d_comp["ra_err"]= float(item_comp["err_ra"])
			d_comp["dec_err"]= float(item_comp["err_dec"])
			d_comp["Speak"]= float(item_comp["peak_flux"])
			d_comp["Speak_err"]= float(item_comp["err_peak_flux"])
			d_comp["S"]= float(item_comp["int_flux"])
			d_comp["S_err"]= float(item_comp["err_int_flux"])
			#d_comp["sx"]= -999 # NOT AVAILABLE 
			#d_comp["sx_err"]= -999 # NOT AVAILABLE 
			#d_comp["sy"]= -999 # NOT AVAILABLE 
			#d_comp["sy_err"]= -999 # NOT AVAILABLE 
			#d_comp["theta"]= -999 # NOT AVAILABLE 
			#d_comp["theta_err"]= -999 # NOT AVAILABLE 
			d_comp["bkg"]= float(item_comp["background"])
			d_comp["rms"]= float(item_comp["local_rms"])
			d_comp["bmaj"]= float(2.0*item_comp["a"])  # a is the semi-major axis
			d_comp["bmaj_err"]= float(2.0*item_comp["err_a"])  # a is the semi-major axis
			d_comp["bmin"]= float(2.0*item_comp["b"])  # b is the semi-minor axis
			d_comp["bmin_err"]= float(2.0*item_comp["err_b"])  # b is the semi-minor axis
			d_comp["pa"]= float(item_comp["pa"])
			d_comp["pa_err"]= float(item_comp["err_pa"])
			#d_comp["bmaj_deconv"]= -999  # NOT AVAILABLE 
			#d_comp["bmin_deconv"]= -999  # NOT AVAILABLE 
			#d_comp["pa_deconv"]= -999  # NOT AVAILABLE 
			#d_comp["morph_label"]= "UNKNOWN"      # NOT AVAILABLE	
			#d_comp["sourceness_label"]= "UNKNOWN" # NOT AVAILABLE	
			#d_comp["sourceness_score"]= -1        # NOT AVAILABLE	
			#d_comp["resolved"]= -1                  # NOT AVAILABLE	
			#d_comp["eccentricity_ratio"]= -1     # NOT AVAILABLE	
			#d_comp["area_ratio"]= -1          # NOT AVAILABLE	
			#d_comp["rot_angle_vs_beam"]= -1          # NOT AVAILABLE	
			d_comp["fit_flags"]= str(item_comp["flags"])
			d_comp["residual_mean"]= float(item_comp["residual_mean"])
			d_comp["residual_std"]= float(item_comp["residual_std"])
			d_comp["psf_a"]= float(item_comp["psf_a"])
			d_comp["psf_b"]= float(item_comp["psf_b"])
			d_comp["psf_pa"]= float(item_comp["psf_pa"])
			
			# - Append component to island fit info components
			idict["fit_info"]["components"].append(d_comp)
		
		# - Append island dict to source
		sdict["islands"].append(idict)
			
		# - Append source dict to main dict
		d["sources"].append(sdict)	
			
	return d			
			

##############
##   MAIN   ##
##############
def main():
	"""Main function"""
	
	#===========================
	#==   PARSE ARGS
	#===========================
	logger.info("Parse script args ...")
	try:
		args= get_args()
	except Exception as ex:
		logger.error("Failed to get and parse options (err=%s)",str(ex))
		return 1

	# - Input catalog ascii files
	inputfile_island= args.inputfile_island
	inputfile_comp= args.inputfile_comp
	
	# - Check input filenames
	if inputfile_island=="" or inputfile_comp=="":
		err= "One/both input catalog filenames are empty!"
		logger.error(err)
		raise RuntimeError(err) from exc
	
	inputfile_basenoext_island= os.path.splitext(os.path.basename(inputfile_island))[0]
	inputfile_basenoext_island= inputfile_basenoext_island.strip("_isle")
	inputfile_basenoext_comp= os.path.splitext(os.path.basename(inputfile_comp))[0]
	
	# - Set output filenames
	outfile= args.outfile
	if args.outfile=="":
		outfile= inputfile_basenoext_island + '.json'
		
	#===========================
	#==   READ INPUT CATALOGS
	#===========================
	logger.info(f"Reading input island catalog file {inputfile_island} ...")
	t_island= Table.read(inputfile_island, format="ascii")

	logger.info(f"Reading input component catalog file {inputfile_comp} ...")
	t_comp= Table.read(inputfile_comp, format="ascii")
	
	#===========================
	#==   MAKE JSON CATALOGS
	#===========================
	logger.info(f"Creating json catalog from input island ({inputfile_island}) and component ({inputfile_comp}) catalog files ...")
	d= make_island_json_catalog(t_island, t_comp)
	
	#===========================
	#==   SAVE JSON CATALOGS
	#===========================
	logger.info(f"Saving json catalog to file {outfile} ...")
	with open(outfile, 'w') as fp:
		json.dump(d, fp, indent=2)

	
###################
##   MAIN EXEC   ##
###################
if __name__ == "__main__":
	sys.exit(main())
