local QBCore = exports['qb-core']:GetCoreObject()

local function cv(amount)
    local formatted = amount
    while true do formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2') if (k==0) then break end Wait(0) end
    return formatted
end

AddEventHandler('onResourceStart', function(resource) if GetCurrentResourceName() ~= resource then return end
	for k, v in pairs(Config.Jobs) do if not QBCore.Shared.Jobs[k] then print("Jim-Payments: Config.Jobs searched for job '"..k.."' and couldn't find it in the Shared") end end
end)

QBCore.Commands.Add("cashregister", "Use mobile cash register", {}, false, function(source) TriggerClientEvent("jim-payments:client:Charge", source, {}, true) end)

RegisterServerEvent('jim-payments:Tickets:Give', function(data, biller)
	--Find the biller from their citizenid
	if not biller then
		for k, v in pairs(QBCore.Functions.GetPlayers()) do
		local Player = QBCore.Functions.GetPlayer(v)
			if Player.PlayerData.citizenid == data.senderCitizenId then	biller = Player	end
		end
		TriggerClientEvent('QBCore:Notify', biller.PlayerData.source, data.sender.." Paid their $"..data.amount.." invoice", "success")
	end
	local duty = true
	if biller.PlayerData.job.onduty then duty = true else duty = false end
	if Config.Manage then exports["qb-management"]:AddMoney(tostring(biller.PlayerData.job.name), data.amount) 
		if Config.Debug then print("QB-Management: Adding $"..data.amount.." to account '"..tostring(biller.PlayerData.job.name).."'") end
	else TriggerEvent("qb-bossmenu:server:addAccountMoney", tostring(biller.PlayerData.job.name), data.amount) 
		if Config.Debug then print("QB-BossMenu: Adding $"..data.amount.." to account '"..tostring(biller.PlayerData.job.name).."'") end
	end
	-- If ticket system enabled, do this
	if duty and Config.TicketSystem then
		if data.amount >= Config.Jobs[data.society].MinAmountforTicket then
			for k, v in pairs(QBCore.Functions.GetPlayers()) do
				local Player = QBCore.Functions.GetPlayer(v)
				if Player ~= nil then
					if Player.PlayerData.job.name == data.society and Player.PlayerData.job.onduty then
						Player.Functions.AddItem('payticket', 1, false, {["quality"] = nil})
						TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Receipt received', 'success')
						TriggerClientEvent('inventory:client:ItemBox', Player.PlayerData.source, QBCore.Shared.Items['payticket'], "add", 1) 
					end
				end
			end
		end
	end
	-- Commission section, does each config option separately
	-- local comm = tonumber(Config.Jobs[data.society].Commission)
	if false then
		if Config.CommissionLimit and data.amount < Config.Jobs[data.society].MinAmountforTicket then return end
		if Config.CommissionDouble then	
			biller.Functions.AddMoney("bank", math.floor(tonumber(data.amount) * (comm *2)))
			TriggerClientEvent("QBCore:Notify", biller.PlayerData.source, "Recieved $"..math.floor(tonumber(data.amount) * (comm *2)).." in Commission", "success")
		else biller.Functions.AddMoney("bank",  math.floor(tonumber(data.amount) *comm))
			TriggerClientEvent("QBCore:Notify", biller.PlayerData.source, "Recieved $"..math.floor(tonumber(data.amount) * comm).." in Commission", "success")
		end
		if Config.CommissionAll then
			for k, v in pairs(QBCore.Functions.GetPlayers()) do
				local Player = QBCore.Functions.GetPlayer(v)
				if Player ~= nil and Player ~= biller then
					if Player.PlayerData.job.name == data.society and Player.PlayerData.job.onduty then
						Player.Functions.AddMoney("bank",  math.floor(tonumber(data.amount) * comm))
						TriggerClientEvent("QBCore:Notify", Player.PlayerData.source, "Recieved $"..math.floor(tonumber(data.amount) * comm).." in Commission", "success")
					end
				end
			end
		end
	end

end)

RegisterServerEvent('jim-payments:Tickets:Sell', function()
    local Player = QBCore.Functions.GetPlayer(source)
	if Player.Functions.GetItemByName("payticket") == nil then TriggerClientEvent('QBCore:Notify', source, "No tickets to trade", 'error') return
	else
		tickets = Player.Functions.GetItemByName("payticket").amount
		Player.Functions.RemoveItem('payticket', tickets)
		pay = (tickets * Config.Jobs[Player.PlayerData.job.name].PayPerTicket)
		Player.Functions.AddMoney('bank', pay, 'ticket-payment')
		TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['payticket'], "remove", tickets)
		TriggerClientEvent('QBCore:Notify', source, "Tickets traded: "..tickets.." Total: $"..cv(pay), 'success')
	end
end)

QBCore.Functions.CreateCallback('jim-payments:Ticket:Count', function(source, cb) 
	if QBCore.Functions.GetPlayer(source).Functions.GetItemByName('payticket') == nil then amount = 0
	else amount = QBCore.Functions.GetPlayer(source).Functions.GetItemByName('payticket').amount end 
	cb(amount) 
end)

RegisterServerEvent("jim-payments:server:Charge", function(citizen, price, billtype, img, outside)
	local src = source
    local biller = QBCore.Functions.GetPlayer(src)
    local billed = QBCore.Functions.GetPlayer(tonumber(citizen))
    local amount = tonumber(price)
	local balance = billed.Functions.GetMoney(billtype)
	if amount and amount > 0 then
		if balance < amount then
			TriggerClientEvent("QBCore:Notify", src, "Customer doesn't have enough cash to pay", "error")
			TriggerClientEvent("QBCore:Notify", tonumber(citizen), "You don't have enough cash to pay", "error")
			
			return
		end
		if billtype == "cash" then 
			TriggerClientEvent("jim-payments:client:PayPopup", billed.PlayerData.source, amount, src, billtype, img, biller.PlayerData.job.label)
		elseif billtype == "bank" then
			if Config.PhoneBank == false then
				TriggerClientEvent("jim-payments:client:PayPopup", billed.PlayerData.source, amount, src, billtype, img, biller.PlayerData.job.label)
			else
				if Config.PhoneType == "qb" then
					MySQL.Async.insert(
						'INSERT INTO phone_invoices (citizenid, amount, society, sender, sendercitizenid) VALUES (?, ?, ?, ?, ?)',
						{billed.PlayerData.citizenid, amount, biller.PlayerData.job.name, biller.PlayerData.charinfo.firstname, biller.PlayerData.citizenid})
					TriggerClientEvent('qb-phone:RefreshPhone', billed.PlayerData.source)
				elseif Config.PhoneType == "gks" then
					MySQL.Async.execute('INSERT INTO gksphone_invoices (citizenid, amount, society, sender, sendercitizenid, label) VALUES (@citizenid, @amount, @society, @sender, @sendercitizenid, @label)', {
						['@citizenid'] = billed.PlayerData.citizenid,
						['@amount'] = amount,
						['@society'] = biller.PlayerData.job.name,
						['@sender'] = biller.PlayerData.charinfo.firstname,
						['@sendercitizenid'] = biller.PlayerData.citizenid,
						['@label'] = biller.PlayerData.job.label,
					})
					TriggerClientEvent('qb-phone:RefreshPhone', billed.PlayerData.source)

				end
				TriggerClientEvent('QBCore:Notify', src, 'Invoice Successfully Sent', 'success')
				TriggerClientEvent('QBCore:Notify', billed.PlayerData.source, 'New Invoice Received')
			end
		end
	else TriggerClientEvent('QBCore:Notify', source, "You can't charge $0", 'error') return end
end)

RegisterServerEvent("jim-payments:server:PayPopup", function(data)
	local src = source
    local billed = QBCore.Functions.GetPlayer(src)
    local biller = QBCore.Functions.GetPlayer(tonumber(data.biller))
	local newdata = { senderCitizenId = biller.PlayerData.citizenid, society = biller.PlayerData.job.name, amount = data.amount }
	if data.accept == true then
		billed.Functions.RemoveMoney(tostring(data.billtype), data.amount)
		print(data.amount,biller.PlayerData.job.name)
		TriggerEvent('qb-banking:society:server:DepositMoney', data.amount, biller.PlayerData.job.name)
		TriggerEvent('jim-payments:Tickets:Give', newdata, biller)
		TriggerClientEvent("QBCore:Notify", data.biller, billed.PlayerData.charinfo.firstname.." accepted the $"..data.amount.." payment", "success")
	elseif data.accept == false then
		TriggerClientEvent("QBCore:Notify", src, "You declined the payment")
		TriggerClientEvent("QBCore:Notify", data.biller, billed.PlayerData.charinfo.firstname.." declined the $"..data.amount.." payment", "error")
	end
end)

QBCore.Functions.CreateCallback('jim-payments:MakePlayerList', function(source, cb)
	local onlineList = {}
	for k, v in pairs(QBCore.Functions.GetPlayers()) do
		local P = QBCore.Functions.GetPlayer(v)
		onlineList[#onlineList+1] = { value = tonumber(v), text = "["..v.."] - "..P.PlayerData.charinfo.firstname..' '..P.PlayerData.charinfo.lastname  }
	end
	cb(onlineList) 
end)