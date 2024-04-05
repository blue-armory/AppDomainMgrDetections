from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload_file():
    # Check if the post request has the file part
    if 'file' not in request.files:
        return jsonify({'error': 'No file part in the request'}), 400
    
    file = request.files['file']
    
    if file.filename == '':
        return jsonify({'error': 'No file selected for uploading'}), 400
    
    if file:
        filename = file.filename
        file.save(filename)
        return jsonify({'message': f'File {filename} uploaded successfully'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=True, port=8000)

