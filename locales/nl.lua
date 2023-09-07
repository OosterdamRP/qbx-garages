local Translations = {
    error = {
        no_vehicles = "Er zijn geen voertuigen op deze locatie!",
        not_impound = "Uw voertuig is niet in beslag genomen",
        not_owned = "Dit voertuig kan niet worden opgeslagen",
        not_correct_type = "U kunt dit soort voertuig hier niet opslaan",
        not_enough = "Niet genoeg geld",
        no_garage = "Geen",
        too_far_away = "Te ver weg van een parkeerplaats",
        occupied = "Parkeerplaats is al bezet",
        all_occupied = "Alle parkeerplaatsen zijn bezet",
        no_vehicle = "Er is geen voertuig om te parkeren",
        no_house_keys = "Je hebt niet de sleutels voor deze huisgarage",
    },
    success = {
        vehicle_parked = "Voertuig opgeslagen",
    },
    menu = {
        header = {
            house_garage = "Huisgarage",
            house_car = "Huisgarage %{value}",
            public_car = "Garage | %{value}",
            public_sea = "Botenhuis | %{value}",
            public_air = "Hangar | %{value}",
            job_car = "Job Garage %{value}",
            job_sea = "Job Botenhuis %{value}",
            job_air = "Job Hangar %{value}",
            gang_car = "Gang Garage %{value}",
            gang_sea = "Gang Botenhuis %{value}",
            gang_air = "Gang Hangar %{value}",
            depot_car = "Depot %{value}",
            depot_sea = "Depot %{value}",
            depot_air = "Depot %{value}",
            vehicles = "Beschikbare voertuigen",
            depot = "%{value} [ $%{value2} ]",
            garage = "%{value} [ %{value2} ]",
        },
        text = {
            vehicles = "Bekijk opgeslagen voertuigen!",
            vehicles_desc = "Zie uw eigen voertuigen!",
            depot = "Nummerplaat: %{value} | Brandstof: %{value2} | Motor: %{value3} | Body: %{value4}",
            garage = "Staat: %{value}",
        },
        metadata = {
            plate = "Nummerplaat",
            fuel = "Brandstof",
            engine = "Motor",
            body = "Body",
            tank   = "Tank Health",
            mileage = "Kilometerstand",
        }
    },
    status = {
        out = "Uit",
        garaged = "Garaged",
        impound = "In beslag genomen",
    },
}

if GetConvar('qb_locale', 'en') == 'nl' then
    Lang = Locale:new({
        phrases = Translations,
        warnOnMissing = true,
        fallbackLang = Lang,
    })
end