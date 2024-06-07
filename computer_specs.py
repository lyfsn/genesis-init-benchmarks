# Create argument parser
import argparse
import datetime
import json
import os
import subprocess
import cpuinfo
import psutil
import platform


def print_computer_specs():
    info = "Computer Specs:\n"
    cpu = cpuinfo.get_cpu_info()
    try:
        cpu_freq = psutil.cpu_freq().current
    except AttributeError:
        cpu_freq = "N/A"
    system_info = {
        'Processor': platform.processor(),
        'System': platform.system(),
        'Release': platform.release(),
        'Version': platform.version(),
        'Machine': platform.machine(),
        'Processor Architecture': platform.architecture()[0],
        'RAM': f'{psutil.virtual_memory().total / (1024 ** 3):.2f} GB',
        'CPU': cpu['brand_raw'],
        'Numbers of CPU': cpu['count'],
        'CPU GHz': f'{cpu_freq} MHz' if cpu_freq != "N/A" else "N/A"
    }

    # Print the specifications
    for key, value in system_info.items():
        line = f'{key}: {value}'
        print(line)
        info += line + "\n"
    return info + "\n"

def save_to(output_folder, file_name, content):
    output_path = os.path.join(output_folder, file_name)
    with open(output_path, "w") as file:
        file.write(content)


def main(output_folder):
    # Print Computer specs
    computer_specs = print_computer_specs()
    save_to(output_folder, 'computer_specs.txt', computer_specs)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Computer Specs Script')
    parser.add_argument('--output_folder', type=str, default='./results', help='The folder to save the output files')
    args = parser.parse_args()
    
    main(args.output_folder)
