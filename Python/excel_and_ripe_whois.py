#!/usr/bin/env python3

''' skrypt
-------------------------------------------
This programm compare internal documentation in excel file
that contain IP assignements for clients
against public databases - RIPE whois

Results are presented in separate column
to check if assignements from excel are consistent with whois

1. wczytuje dane z pliku w excel
2. porownuje dane z wpisami w whois.ripe.net i zapisuje do tego samego pliku
   status wpisu w ripe czy przydzial dla odczytanej puli z excel istnieje
   czy nie i czy nazwa jest taka sama jak w excel
3. ** to-do ** porownuje dane z routingiem w POZMAN i zapisuje status
   do tego samego pliku status'''

from openpyxl import load_workbook
# from pprint import pprint
from ipwhois import IPWhois
import shutil
import os

PLIK_ZRODLOWY = "source_file.xlsx"
PLIK_ROBOCZY = "tmp_file.xlsx"
# kolumna do wpisu wynikow z whois
KOLUMNA_WHOIS = 'J'
PLIK_PARAMETRY = [
    {
     "arkusz_nazwa": "sheet-name1",
     "kolumna_pocz": 'A',
     "wers_pocz": 4,
     "wers_kon": 75,
     "pula_glw_z_ripe": "PL-POZMAN-970805"},
    {
     "arkusz_nazwa": "sheet-name2",
     "kolumna_pocz": 'A',
     "wers_pocz": 4,
     "wers_kon": 115,
     "pula_glw_z_ripe": "PL-POZMAN-981026"},
    {
     "arkusz_nazwa": "sheet-name3",
     "kolumna_pocz": 'A',
     "wers_pocz": 4,
     "wers_kon": 32,
     "pula_glw_z_ripe": "PL-POZMAN-20020114"},
    ]
dane_wyj = []


def main(args):
    ''' uruchamiamy glowna funkcje '''

    # print(odczytaj_baze_whois('195.216.99.0'))
    kopiuj_plik()
    odczytaj_plik_excel()


def kopiuj_plik():
    cwd = os.getcwd()
    shutil.copy2(os.path.join(cwd, PLIK_ZRODLOWY),
                 os.path.join(cwd, PLIK_ROBOCZY))


def odczytaj_baze_whois_test(dane):
    ''' test DEV - bedzie do usuniecia '''

    obj = IPWhois('195.216.96.0')
    results = obj.lookup_rdap(depth=1)
    print(results.get("network").get('name'))
    print(results.get("network").get('start_address'))
    print(results.get("network").get('end_address'))


def odczytaj_baze_whois(adres_ip):
    ''' odczytujemy dane z bazy whois '''

    obj = IPWhois(adres_ip)
    results = obj.lookup_rdap(depth=1)
    # pprint(results)
    return (results.get("network").get('name'))


def odczytaj_plik_excel():
    ''' odczytujemy plik excel '''

    wb = load_workbook(filename=PLIK_ROBOCZY, data_only=True)
    # zmienna i do iteracji po listach - arkuszach w dane_wyj
    i = 0
    # iterujemy po arkuszach
    for slownik in PLIK_PARAMETRY:
        print(f"Nazwa arkusza = {slownik.get('arkusz_nazwa')}")
        sheet = wb[slownik.get('arkusz_nazwa')]
        # tworze nowa lista dla iteracji nastepnego arkusza
        # - do listy dodam nowy slownik z danymi
        dane_wyj.append([])
        # wstaw pustakolumne J do wpisywania wynikow
        sheet.insert_cols(10)
        for wersy in range(slownik.get('wers_pocz'),
                           slownik.get('wers_kon')+1):
            # odczytujac komorke z adresem ze zmiennej ze slownika,
            # odczytujemy 4 bajty adresu IP z kolejnych komorek
            kom_1 = chr(ord(slownik.get('kolumna_pocz')))+str(wersy)
            kom_2 = chr(ord(slownik.get('kolumna_pocz'))+1)+str(wersy)
            kom_3 = chr(ord(slownik.get('kolumna_pocz'))+2)+str(wersy)
            kom_4 = chr(ord(slownik.get('kolumna_pocz'))+3)+str(wersy)
            # kom_nazwa - wskazuje indeks  komorki z nazwa klienta np. G4
            kom_nazwa = chr(ord(slownik.get('kolumna_pocz'))+6)+str(wersy)
            # kom_wynik - wskazuje indeks komorki gdzie zapisac wynik
            kom_whois = KOLUMNA_WHOIS+str(wersy)

            # zapis pojedynczego adresu ip z excela do zmiennej
            # adres ip sklada sie z 4 liczb ktore przypisujemy do zmiennych:
            # ip_a, ip_b, ip_c, ip_d
            dane_wyj[i].append({"wers": wersy, "ip_a": sheet[kom_1].value,
                                "ip_b": sheet[kom_2].value,
                                "ip_c": sheet[kom_3].value,
                                "ip_d": sheet[kom_4].value})
            # print(dane_wyj[i])
            adres_ip = str(sheet[kom_1].value) + \
                '.' + str(sheet[kom_2].value) + \
                '.' + str(sheet[kom_3].value) + \
                '.' + str(sheet[kom_4].value)
            # wpisujemy wynik w kolumne J - czyli 9
            wynik_whois = odczytaj_baze_whois(adres_ip)
            # jesli wynik z whois jest zgodny z arkuszem, wpisz do arkusza OK

            # print(f"wynik_whois={wynik_whois}"
            # " komorka={sheet[kom_nazwa].value}")
            if sheet[kom_nazwa].value == wynik_whois:
                wynik_do_zapisu = "OK"
            elif sheet[kom_nazwa].value == "unused" and \
                    wynik_whois.find("PL-POZMAN") > -1:
                wynik_do_zapisu = "OK"
            else:
                wynik_do_zapisu = wynik_whois
            # print(f"wynik_do_zapisu={wynik_do_zapisu}")
            sheet[kom_whois] = wynik_do_zapisu
            print("Pozostala ilosc wersow do odpytania="
                  f"{slownik.get('wers_kon')-wersy}")
        i += 1
    wb.save(filename=PLIK_ROBOCZY)
    # pprint(dane_wyj)
    return (dane_wyj)


if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv))
