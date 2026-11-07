"""Inicia la interfaz web de AutoAudit (solo en la red local)."""
import os
from app.main import app, settings_valid

if __name__ == '__main__':
    settings_valid()
    app.run(host=os.getenv('FLASK_HOST', '127.0.0.1'),
            port=int(os.getenv('FLASK_PORT', '5000')), debug=False)
