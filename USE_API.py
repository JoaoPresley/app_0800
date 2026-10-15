import os
from xml.dom import DOMException
from xml.dom.minidom import Element

import requests
from bs4 import BeautifulSoup
import pandas as pd
from dotenv import load_dotenv
from soupsieve.css_types import Null


class API:
    def __init__(self):
        """Inicializa as variaveis de API e carrega as credenciais do .env."""
        load_dotenv()

        self.__USERNAME = os.getenv("IFS_USERNAME")
        self.__PASSWORD = os.getenv("IFS_PASSWORD")
        self.__login_url = "https://ifs10pro.msgas.com.br:48080/openid-connect-provider"
        self.__example_get_url = "https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/ActiveWorkOrdersHandling.svc/ActiveSeparateSet?$top=1"

        if not all([self.__USERNAME, self.__PASSWORD]):
            raise ValueError("Variáveis de ambiente (BASE_API_URL, IFS_USERNAME, IFS_PASSWORD) não foram definidas.")

        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"
        })

    def get_data(self, url_api):
        """Consome a API e retorna o json.
        """
        # Verifica se foi realizado login
        try:
            response = self.session.get(self.__login_url, allow_redirects=True)
            if "login?rf=" in response.url:
                print("API: Realizando login...")
                self.__login(response)
        except requests.exceptions.RequestException as err:
            print(f"Erro ao tentar logar: {err}")
        #Se já está logado continua a requisição
        try:
            response = self.session.get(url_api, allow_redirects=True)
            response.raise_for_status()
            return response

        except requests.exceptions.RequestException as err:
            print(f"Erro inesperado na requisição: {err}")
            raise

    def post_data(self, url_api, payload=None, header=None):
        """Consome a API e retorna o json.
        """
        #Valida entradas.
        if not payload:
            payload = {}
        if not header:
            header = {}
        # Verifica se foi realizado login
        try:
            response = self.session.get(self.__login_url, allow_redirects=True)
            if "login?rf=" in response.url:
                print("API: Realizando login...")
                self.__login(response)
        except requests.exceptions.RequestException as err:
            print(f"Erro ao tentar logar: {err}")
        try:
            response = self.session.post(url_api, allow_redirects=True, json=payload, headers=header)
            response.raise_for_status()
            return response

        except requests.exceptions.RequestException as err:
            print(f"Erro inesperado na requisição: {err}")
            raise

    def patch_data(self, url_api, payload):
        """Consome a API e retorna o json.
        """
        # Verifica se foi realizado login
        try:
            response = self.session.get(self.__login_url, allow_redirects=True)
            if "login?rf=" in response.url:
                print("API: Realizando login...")
                self.__login(response)
        except requests.exceptions.RequestException as err:
            print(f"Erro ao tentar logar: {err}")
        try:
            response = self.session.patch(url_api, allow_redirects=True, json=payload)
            response.raise_for_status()
            return response

        except requests.exceptions.RequestException as err:
            print(f"Erro inesperado na requisição: {err}")
            raise

    def __login(self, response: requests.Response) -> requests.Response:
        """Realiza o fluxo de login no IFS.
        Atualizada o header da sessão para capturar a chave CSRF"""
        login_url = response.url #Url para realizar login, gerada unicamente
        try:
            # Tenta logar no sistema
            payload = {"username": self.__USERNAME, "password": self.__PASSWORD}
            response_login = self.session.post(login_url, data=payload, allow_redirects=True)
            response_login.raise_for_status()

            # Caso o usuário ou senha inseridos não consigam acessar o sistema
            if "login?rf=" in response_login.url:
                raise ConnectionError("Falha de login: usuário ou senha incorretos.")

            # Realiza o callback e captura o token CSRF
            response_callback = self.session.get(self.__example_get_url, allow_redirects=True)
            soup = BeautifulSoup(response_callback.text, "html.parser")
            form = soup.find("form")
            if not form:
                raise DOMException("Falha no html de callback: sem divisão <form>")

            callback_url = form.get("action") # URL
            payload = { # Data
                input_tag.get("name"): input_tag.get("value")
                for input_tag in form.find_all("input") if input_tag.get("name")
            }
            feedback = self.session.post(callback_url, data=payload, allow_redirects=True)
            feedback.raise_for_status()

            # atualiza o CSRF
            token = self.session.cookies.get("XSRF-TOKEN")
            if token:
                self.session.headers.update({"X-XSRF-TOKEN": token})

        except requests.exceptions.RequestException as err:
            print(f"Erro na etapa de login: {err}")