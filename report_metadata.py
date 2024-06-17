import os
import sys
import json
import yaml

def read_computer_specs(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()
    specs = {}
    for line in lines[1:]:
        key, value = line.split(": ")
        specs[key.strip()] = value.strip()
    return specs

def read_images(file_path):
    with open(file_path, 'r') as file:
        images = yaml.safe_load(file)
    return images

def save_metadata(computer_specs, images, output_path):
    metadata = {
        'computer_specs': computer_specs,
        'images': images
    }
    with open(output_path, 'w') as file:
        json.dump(metadata, file, indent=4)

def main(date, data_type):
    base_path = f"results-{date}/{data_type}"
    computer_specs_path = os.path.join(base_path, "computer_specs.txt")
    images_path = "./images.yaml"
    output_path = os.path.join(base_path, "reports", "metadata.json")

    if not os.path.exists(os.path.dirname(output_path)):
        os.makedirs(os.path.dirname(output_path))

    computer_specs = read_computer_specs(computer_specs_path)
    images = read_images(images_path)
    save_metadata(computer_specs, images, output_path)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <date> <data_type>")
        sys.exit(1)

    date = sys.argv[1]
    data_type = sys.argv[2]
    main(date, data_type)