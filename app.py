
from flask import Flask, request, render_template
from prometheus_flask_exporter import PrometheusMetrics
import joblib
import numpy as np
import pandas as pd
import os

# Load trained models and encoder
model1 = joblib.load('model_decision_tree_gini.pkl')
model2 = joblib.load('model_decision_tree_entropy.pkl')
le = joblib.load('label_encoder.pkl')

# Load symptoms list and additional info
severity_df = pd.read_csv('Project_dataset/symptom-severity.csv')
desc_df = pd.read_csv('Project_dataset/symptom_Description.csv')
prec_df = pd.read_csv('Project_dataset/symptom_precaution.csv')

symptoms_list = sorted(severity_df['Symptom'].str.strip().str.replace(' ', '_').str.lower().unique())

app = Flask(__name__)
metrics = PrometheusMetrics(app)
metrics.info('app_info', 'Disease Prediction System', version='1.0.0')

@app.route('/')
def index():
    return render_template('index.html', symptoms=symptoms_list)

@app.route('/predict', methods=['POST'])
def predict():
    selected_symptoms = request.form.getlist('symptoms')
    input_data = [1 if symptom in selected_symptoms else 0 for symptom in symptoms_list]
    
    pred1 = model1.predict([input_data])[0]
    pred2 = model2.predict([input_data])[0]
    final_pred = le.inverse_transform([np.bincount([pred1, pred2]).argmax()])[0]

    description = desc_df[desc_df['Disease'].str.lower() == final_pred]['Description'].values
    precautions = prec_df[prec_df['Disease'].str.lower() == final_pred].values

    description_text = description[0] if description.size else "No description available."
    precaution_list = [p for p in precautions[0][1:] if pd.notna(p)] if precautions.size else []

    return render_template('result.html', disease=final_pred.title(), 
                           description=description_text, precautions=precaution_list)


if __name__ == '__main__':
	app.run(host='0.0.0.0', port=5000)
