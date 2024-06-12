import argparse
import json
import os
import numpy as np
import yaml
from bs4 import BeautifulSoup

def calculate_metrics(values):
    if not values:
        return {'max': None, 'p50': None, 'p95': None, 'p99': None, 'min': None, 'count': 0}
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
        if filename.endswith('.txt') and filename != "computer_specs.txt":
            parts = filename.split('_')
            if len(parts) < 4:
                print(f"Filename {filename} does not match expected pattern")
                continue
            
            client, run, part, size, mem, is_mem = '', '', '', '', '', False
            if len(parts) == 4:
                client, run, part, size = parts
                size = size.replace('.txt', '')
                is_mem = False
            elif len(parts) == 5:
                client, run, part, size, mem = parts
                is_mem = True
            
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
            if size not in client_results[client]:
                client_results[client][size] = {}
            if part not in client_results[client][size]:
                client_results[client][size][part] = {'time': [], 'mem': []}
                
            if is_mem:
                client_results[client][size][part]['mem'].append(value)
            else:
                client_results[client][size][part]['time'].append(value)
            
            print(f"Added value for size {size}, client {client}, part {part}: {value}")
    return client_results

def process_client_results(client_results):
    processed_results = {}
    for client, sizes in client_results.items():
        processed_results[client] = {}
        for size, parts in sizes.items():
            processed_results[client][size] = {}
            for part, values in parts.items():
                time_metrics = calculate_metrics(values['time'])
                mem_metrics = calculate_metrics(values['mem'])
                processed_results[client][size][part] = {'time': time_metrics, 'mem': mem_metrics}
    return processed_results

def generate_json_report(processed_results, results_path):
    report_path = os.path.join(results_path, 'reports')
    os.makedirs(report_path, exist_ok=True)
    with open(os.path.join(report_path, 'results.json'), 'w') as json_file:
        json.dump(processed_results, json_file, indent=4)

def ms_to_readable_time(ms):
    if ms is None:
        return "N/A"
    minutes = ms // 60000
    seconds = (ms % 60000) // 1000
    if minutes == 0:
        return f"{seconds}s"
    return f"{minutes}min{seconds}s"

def generate_html_report(processed_results, results_path, images, computer_spec):
    html_content = (
        '<!DOCTYPE html>'
        '<html lang="en">'
        '<head>'
        '  <meta charset="UTF-8">'
        '  <meta name="viewport" content="width=device-width, initial-scale=1.0">'
        '  <title>Benchmarking Report</title>'
        '  <style>'
        '    body { font-family: Arial, sans-serif; }'
        '    table { border-collapse: collapse; margin-bottom: 20px; }'
        '    th, td { border: 1px solid #ddd; padding: 8px; text-align: center; }'
        '    th { background-color: #f2f2f2; }'
        '  </style>'
        '</head>'
        '<body>'
        '<h2>Benchmarking Report</h2>'
        f'<h3>Computer Specs</h3><pre>{computer_spec}</pre>'
    )
    
    image_json = json.loads(images)
    with open('images.yaml', 'r') as f:
        el_images = yaml.safe_load(f)["images"]
    
    for client, sizes in processed_results.items():
        image_to_print = image_json.get(client, el_images.get(client.split("_")[0], 'default'))
        
        html_content += f'<h3>{client.capitalize()} - {image_to_print}</h3>'
        html_content += (
            '<table>'
            '<thead>'
            '<tr>'
            '<th>Genesis File Size</th>'
            '<th>Part</th>'
            '<th>Max</th>'
            '<th>p50</th>'
            '<th>p95</th>'
            '<th>p99</th>'
            '<th>Min</th>'
            '<th>Count</th>'
            '</tr>'
            '</thead>'
            '<tbody>'
        )
        
        sorted_sizes = sorted(sizes.items(), key=lambda x: int(x[0].replace('M', '')))
        for size, parts in sorted_sizes:
            sorted_parts = sorted(parts.items(), key=lambda x: (x[0],))
            for part, metrics in sorted_parts:
                html_content += (
                    f'<tr><td>{size}</td>'
                    f'<td>{part}</td>'
                    f'<td>{ms_to_readable_time(metrics["time"]["max"])} ({metrics["mem"]["max"]}M)</td>'
                    f'<td>{ms_to_readable_time(metrics["time"]["p50"])} ({metrics["mem"]["p50"]}M)</td>'
                    f'<td>{ms_to_readable_time(metrics["time"]["p95"])} ({metrics["mem"]["p95"]}M)</td>'
                    f'<td>{ms_to_readable_time(metrics["time"]["p99"])} ({metrics["mem"]["p99"]}M)</td>'
                    f'<td>{ms_to_readable_time(metrics["time"]["min"])} ({metrics["mem"]["min"]}M)</td>'
                    f'<td>{metrics["time"]["count"]}</td></tr>'
                )
        
        html_content += '</tbody></table>'
    
    html_content += '</body></html>'
    
    soup = BeautifulSoup(html_content, 'html.parser')
    formatted_html = soup.prettify()
    
    report_path = os.path.join(results_path, 'reports')
    os.makedirs(report_path, exist_ok=True)
    with open(os.path.join(report_path, 'report.html'), 'w') as html_file:
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
    computer_spec_path = os.path.join(results_path, "computer_specs.txt")
    if os.path.exists(computer_spec_path):
        with open(computer_spec_path, 'r') as file:
            computer_spec = file.read().strip()
    else:
        computer_spec = "Not available"

    client_results = get_client_results(results_path)
    print("Client Results:", client_results)  # Debug information

    processed_results = process_client_results(client_results)
    print("Processed Results:", processed_results)  # Debug information

    generate_json_report(processed_results, results_path)
    generate_html_report(processed_results, results_path, images, computer_spec)

    print('Done!')

if __name__ == '__main__':
    main()
