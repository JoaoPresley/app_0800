from select import select
from soupsieve.css_types import Null

from USE_API import API
from datetime import datetime
from dotenv import load_dotenv
import os
# Carrega variaveis do .env
load_dotenv()

def make_descricao():
    """Funcao simulando formulário que será preenchido no app

    :return: titulo, descricao, hora_chamada, hora_init_atendimento, hora_term_atendimento
    """
    ocorrecia = {
        1: "Falta de gás",
        2: "Cheiro de gás",
        3: "Vazamento de gás",
        4: "Incêndio",
        5: "Pressão alterada",
        6: "Solictação de acompanhamento",
        7: "Trote",
        8: "Teste de comunicação",
        9: "Outros"
    }
    op = int(input(f"{ocorrecia}\nEscolha um numero: "))
    if(op == 7 or op == 8 or op == 9):
        autor_da_chamada = str(input("Digite o nome do autor da chamada: "))
        numero_do_autor = str(input("Digite o numero do autor: "))
        hora_chamada = str(input("Digite a hora da chamada: "))
        detalhes = str(input("Digite o nome do detalhes da chamada: "))
        titulo = f"0800 - {ocorrecia[op]}"
        descricao = f"Ligação de {autor_da_chamada if not "" else Null} - {numero_do_autor}"
        return titulo, descricao
    elif(op == 6):
        autor_da_chamada = str(input("Digite o nome do autor da chamada: "))
        cliente = str(input("Digite o nome da empresa solicitante: "))
        hora_chamada = str(input("Digite a hora da chamada: "))
        hora_init_atendimento = str(input("Digite a hora do inico do atendimento: "))
        hora_term_atendimento = str(input("Digite a hora do termino do atendimento: "))
        detalhes = str(input("Digite o nome do detalhes do atendimento: "))
    else:
        autor_da_chamada = str(input("Digite o nome do autor da chamada: "))
        cliente = str(input("Digite o nome do cliente da chamada: "))
        hora_chamada = str(input("Digite a hora da chamada: "))
        hora_init_atendimento = str(input("Digite a hora do inico do atendimento: "))
        hora_term_atendimento = str(input("Digite a hora do termino do atendimento: "))
        detalhes = str(input("Digite o nome do detalhes do atendimento: "))

    titulo = f"0800 - {ocorrecia[op]}"
    descricao = (f"Ligação realizada por {autor_da_chamada}/ Cliente: {cliente} às {hora_chamada}.\n"
                 f"Detalhes do atendimento: {detalhes}.\n"
                 f"Hora de inicio ao atendimento: {hora_init_atendimento}.\n"
                 f"Hora do termino ao atendimento: {hora_term_atendimento}.\n")

    return titulo, descricao, hora_chamada, hora_init_atendimento, hora_term_atendimento
def make_payload(titulo, descricao, chamada, inicio, fim):
    """Trata cada um dos dados e cria o json para enviar no payload

    :param titulo:
    :param descricao:
    :param chamada:
    :param inicio:
    :param fim:
    :return: payload para a requisição post
    """
    # Data atual
    data = datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ")

    # Chamada: de string para datetime (strptime) -> de datetime para string (strftime)
    chamada_ = datetime.strptime(chamada, "%d/%m/%Y %H:%M")
    chamada_final = chamada_.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Início: CORRIGIDO para strptime na primeira linha
    inicio_ = datetime.strptime(inicio, "%d/%m/%Y %H:%M")
    inicio_final = inicio_.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Fim: CORRIGIDO para strptime na primeira linha
    fim_ = datetime.strptime(fim, "%d/%m/%Y %H:%M")
    fim_final = fim_.strftime("%Y-%m-%dT%H:%M:%SZ")

    reportado = os.getenv("IFS_USERNAME").upper()
    site = "CGR"
    Org_manut = "OCGR"

    return {
        "RegDate": data,
        "ErrDescr": titulo,
        "ErrDescrLo": descricao,
        "RealSDate":inicio_final , # Hora de chegada ao local
        "RealFDate":fim_final, # Hora do termino do atendimento
        "EarliestStartDate":chamada_final, # Hora da chamada
        "ReportedBy": reportado,
        "OrgCode": Org_manut,
        "WorkTypeId": "0800",
        "Contract": site,
        "MchCodeContract": site,
        "PriorityId": "0",
        "ConnectionType": "Equipment",
        "ExcludeFromScheduling": False,
        "FinishWithTask": False,
        "ActivityConnection": False,
        "PmGroupMergeDb": False,
        "SchedMaintWinDb": True,
    }
# Inicia API
api = API()
feed_payload = make_descricao()
# Link da API para abrir OSs
abrir_OS =  "https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/ActiveWorkOrdersHandling.svc/ActiveSeparateSet"
#   Requisição POST
OS = api.post_data(url_api=abrir_OS, payload=make_payload(
                                            titulo=feed_payload[0],
                                            descricao=feed_payload[1],
                                            chamada=feed_payload[2],
                                            inicio=feed_payload[3],
                                            fim=feed_payload[4])
                     )
print("OS: \n" + OS.text)
# Link para inserir tarefa na OS
abrir_tarefa_na_OS = f'https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/ActiveWorkOrdersHandling.svc/ActiveSeparateSet(WoNo={OS.json()['WoNo']})/WorkTaskeArray'
# Requisição POST
tarefa = api.post_data(url_api=abrir_tarefa_na_OS,
                       payload={
                           #Obrigatórios
                            "WoNo": OS.json()["WoNo"],
                            "Site": OS.json()["Contract"],
                            "OrganizationSite": OS.json()["Contract"],
                            "OrganizationId": OS.json()["OrgCode"],
                            "Description": OS.json()["ErrDescr"],
                            "ExcludeFromScheduling": False,
                           #Inseridos
                            "PreparedBy": OS.json()["ReportedBy"],
                            "ReportedBy": OS.json()["ReportedBy"],
                            "WorkTypeId": OS.json()["WorkTypeId"],
                            "PriorityId": OS.json()["PriorityId"],
                            "ReportedDate": OS.json()["RegDate"],
                            "ActualStart": OS.json()["RealSDate"],
                            "ActualFinish": OS.json()["RealFDate"],
                            "EarliestStart": OS.json()["EarliestStartDate"],
                            "PerformedWork": OS.json()["ErrDescrLo"]
                            })
print("tarefa: \n" + tarefa.text)
# Mudar status da tarefa
#   API para finalizar tarefa
end_work_tarefa = f"https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/WorkTaskHandling.svc/JtTaskSet(TaskSeq={tarefa.json()['TaskSeq']})/IfsApp.WorkTaskHandling.JtTask_EndWork"
update = api.post_data(url_api=end_work_tarefa, header={"If-Match": tarefa.headers["ETag"]})
update.raise_for_status()

#update_task_url = f"https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/WorkTaskHandling.svc/JtTaskSet(TaskSeq={tarefa.json()["TaskSeq"]})/IfsApp.WorkTaskHandling.JtTask_StartWork"

