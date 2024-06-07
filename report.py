import argparse
import json
import os
import numpy as np
import yaml
from bs4 import BeautifulSoup

def calculate_metrics(values):
    if not values:
        return {
            'max': None,
            'p50': None,
            'p95': None,
            'p99': None,
            'min': None,
            'count': 0
        }
    values = np.array(values, dtype=int)
    return {
        'max': int(np.max(values)),
        'p50': int(np.percentile(values, 50)),
        'p95': int(np.percentile(values, 95)),
        'p99': int(np.percentile(values, 99)),
        'min': int(np.min(values)),
        'count': len(values)
    }

def get_client_results(results_path):
    client_results = {}
    for filename in os.listdir(results_path):
        if filename.endswith('.txt'):
            parts = filename.rsplit('_', 2)
            if len(parts) == 3:
                client, run, part = parts
                part = part.replace('.txt', '')
                try:
                    run = int(run)
                    with open(os.path.join(results_path, filename), 'r') as file:
                        value = int(file.read().strip())
                except ValueError:
                    print(f"Skipping file {filename} due to invalid content")
                    continue
                except Exception as e:
                    print(f"Error reading file {filename}: {e}")
                    continue
                if client not in client_results:
                    client_results[client] = {}
                if part not in client_results[client]:
                    client_results[client][part] = []
                client_results[client][part].append(value)
                print(f"Added value for {client} run {run} part {part}: {value}")
            else:
                print(f"Filename {filename} does not match expected pattern")
    return client_results

def process_client_results(client_results):
    processed_results = {}
    for client, parts in client_results.items():
        processed_results[client] = {}
        for part, values in parts.items():
            processed_results[client][part] = calculate_metrics(values)
    return processed_results

def generate_json_report(processed_results, results_path):
    with open(os.path.join(results_path, 'reports', 'results.json'), 'w') as json_file:
        json.dump(processed_results, json_file, indent=4)

def ms_to_readable_time(ms):
    if ms is None:
        return "N/A"
    minutes = ms // 60000
    seconds = (ms % 60000) // 1000
    return f"{minutes}min{seconds}s"

def generate_html_report(processed_results, results_path, images, computer_spec):
    html_content = ('<!DOCTYPE html>'
                    '<html lang="en">'
                    '<head>'
                    '    <meta charset="UTF-8">'
                    '    <meta name="viewport" content="width=device-width, initial-scale=1.0">'
                    '    <title>Benchmarking Report</title>'
                    '    <style>'
                    '        body { font-family: Arial, sans-serif; }'
                    '        table { border-collapse: collapse; margin-bottom: 20px; }'
                    '        th, td { border: 1px solid #ddd; padding: 8px; text-align: center; }'
                    '        th { background-color: #f2f2f2; }'
                    '    </style>'
                    '</head>'
                    '<body>'
                    '<h2>Benchmarking Report</h2>'
                    f'<h3>Computer Specs</h3><pre>{computer_spec}</pre>')
    image_json = json.loads(images)
    for client, parts in processed_results.items():
        image_to_print = image_json.get(client, 'default')
        if image_to_print == 'default':
            with open('images.yaml', 'r') as f:
                el_images = yaml.safe_load(f)["images"]
            client_without_tag = client.split("_")[0]
            image_to_print = el_images.get(client_without_tag, 'default')
        
        html_content += f'<h3>{client.capitalize()} - {image_to_print}</h3>'
        html_content += ('<table>'
                         '<thead>'
                         '<tr>'
                         '<th>Metric</th>'
                         '<th>First</th>'
                         '<th>Second</th>'
                         '</tr>'
                         '</thead>'
                         '<tbody>'
                         f'<tr><td>Max</td><td>{ms_to_readable_time(parts["first"]["max"])}</td><td>{ms_to_readable_time(parts["second"]["max"])}</td></tr>'
                         f'<tr><td>p50</td><td>{ms_to_readable_time(parts["first"]["p50"])}</td><td>{ms_to_readable_time(parts["second"]["p50"])}</td></tr>'
                         f'<tr><td>p95</td><td>{ms_to_readable_time(parts["first"]["p95"])}</td><td>{ms_to_readable_time(parts["second"]["p95"])}</td></tr>'
                         f'<tr><td>p99</td><td>{ms_to_readable_time(parts["first"]["p99"])}</td><td>{ms_to_readable_time(parts["second"]["p99"])}</td></tr>'
                         f'<tr><td>Min</td><td>{ms_to_readable_time(parts["first"]["min"])}</td><td>{ms_to_readable_time(parts["second"]["min"])}</td></tr>'
                         f'<tr><td>Count</td><td>{parts["first"]["count"]}</td><td>{parts["second"]["count"]}</td></tr>'
                         '</tbody></table>')
    html_content += '</body></html>'
    
    soup = BeautifulSoup(html_content, 'html.parser')
    formatted_html = soup.prettify()
    with open(os.path.join(results_path, 'reports', 'report.html'), 'w') as html_file:
        html_file.write(formatted_html)

def main():
    parser = argparse.ArgumentParser(description='Benchmark script')
    parser.add_argument('--resultsPath', type=str, help='Path to gather the results', default='results')
    parser.add_argument('--images', type=str, help='Image values per each client',
                        default='{ "nethermind": "default", "besu": "default", "geth": "default", "reth": "default", "erigon": "default" }')

    args = parser.parse_args()

    results_path = args.resultsPath
    images = args.images
    reports_path = os.path.join(results_path, 'reports')
    os.makedirs(reports_path, exist_ok=True)

    # Get the computer spec
    computer_spec = "Unknown"
    spec_file = os.path.join(results_path, 'computer_specs.txt')
    if os.path.exists(spec_file):
        with open(spec_file, 'r') as file:
            computer_spec = file.read().strip()

    client_results = get_client_results(results_path)
    print("Client Results:", client_results)  # Add debug information

    processed_results = process_client_results(client_results)
    print("Processed Results:", processed_results)  # Add debug information

    generate_json_report(processed_results, results_path)
    generate_html_report(processed_results, results_path, images, computer_spec)

    print('Done!')

if __name__ == '__main__':
    main()
