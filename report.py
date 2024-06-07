import argparse
import json
import os
import numpy as np
import yaml
from bs4 import BeautifulSoup

def calculate_metrics(values):
    max_value = np.max(values)
    p50_value = np.percentile(values, 50)
    p95_value = np.percentile(values, 95)
    p99_value = np.percentile(values, 99)
    min_value = np.min(values)
    return {
        'max': max_value,
        'p50': p50_value,
        'p95': p95_value,
        'p99': p99_value,
        'min': min_value,
        'count': len(values)
    }

def get_client_results(results_path):
    client_results = {}
    for filename in os.listdir(results_path):
        if filename.endswith('.txt'):
            parts = filename.rsplit('_', 2)
            if len(parts) == 3:
                client, run, _ = parts
                run = int(run)
                with open(os.path.join(results_path, filename), 'r') as file:
                    value = float(file.read().strip())
                if client not in client_results:
                    client_results[client] = {}
                if run not in client_results[client]:
                    client_results[client][run] = []
                client_results[client][run].append(value)
    return client_results

def generate_json_report(client_results, results_path):
    metrics = {}
    for client, runs in client_results.items():
        all_values = [value for run_values in runs.values() for value in run_values]
        metrics[client] = calculate_metrics(all_values)
    with open(os.path.join(results_path, 'reports', 'results.json'), 'w') as json_file:
        json.dump(metrics, json_file, indent=4)

def generate_html_report(client_results, results_path, images, computer_spec):
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
    for client, runs in client_results.items():
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
                         '<th>Run</th>'
                         '<th>Max (ms)</th>'
                         '<th>p50 (ms)</th>'
                         '<th>p95 (ms)</th>'
                         '<th>p99 (ms)</th>'
                         '<th>Min (ms)</th>'
                         '<th>Count</th>'
                         '</tr>'
                         '</thead>'
                         '<tbody>')
        for run, values in runs.items():
            metrics = calculate_metrics(values)
            html_content += (f'<tr>'
                             f'<td>{run}</td>'
                             f'<td>{metrics["max"]}</td>'
                             f'<td>{metrics["p50"]}</td>'
                             f'<td>{metrics["p95"]}</td>'
                             f'<td>{metrics["p99"]}</td>'
                             f'<td>{metrics["min"]}</td>'
                             f'<td>{metrics["count"]}</td>'
                             '</tr>')
        html_content += '</tbody></table>'
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
    generate_json_report(client_results, results_path)
    generate_html_report(client_results, results_path, images, computer_spec)

    print('Done!')

if __name__ == '__main__':
    main()
