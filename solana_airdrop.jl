# Prog   : solana_airdrop.jl
# Auth   : MrChaos
# E-Mail : mrchaos@naver.com
# 백그라운드 실행 : nohup julia solana_airdrop.jl > log &

using Printf:@printf
using Dates

# true : devnet, false : testnet
isdev = true

"Run a Cmd object, returning the stdout & stderr contents plus the exit code"
function execute(cmd::Cmd)
  out = Pipe()
  err = Pipe()

  process = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err))
  close(out.in)
  close(err.in)

  (
    stdout = String(read(out)),
    stderr = String(read(err)),
    code = process.exitcode
  )
end
function execute(str::String)
  cmd = Cmd(Vector{String}(split(str)))
  return execute(cmd)
end
function get_balance(sbal::String)
    regex = r"([0-9\.]+[\s]).*"
    m = match(regex,sbal)
    return parse(Float64,strip(m[1]))
end

if isdev
  url = "https://api.devnet.solana.com"
  airdrop_account = "9B5XszUGdMaxCZ7uSQhPzdks5ZQSmWxrmzCSvtJ6Ns6g"
  amount = 2
  max_amount = 1000000
else
  url = "https://api.testnet.solana.com"
  airdrop_account = "4ETf86tK7b4W72f27kNLJLgRWi9UfJjgH4koHGUXMFtn"
  amount = 1
  max_amount = 2000000
end
amount_sum = 0

# Airdrop을 모으는 지갑주소
my_account = "92GHwaKBP4PnkTZur2XrW8atw5GGth7YVv9g3z9Y8akc"

# Airdrop을 받는 임시 지갑
tmp_key = "tmp-account.json"
gas_fee = 0.0001

wait_airdrop = 10   # airdrop 성공후 대기 시간
wait_check = 60*5  # 잔고 부족 후 대기 시간
wait_next_max =  60*60*24  # max amount 달성 후 대기 시간

cmd_wallet_create = "solana-keygen new --no-passphrase -o $(tmp_key)"

if isfile(tmp_key)
  code_wallet = 0
else
  # 지갑생성
  out,error,code_wallet = execute(cmd_wallet_create)
end

while true
  # 지갑생성 성공
  println(string("-------------- ",now()," --------------"))
  flush(stdout)
  if code_wallet == 0
    # airdrop address에서 잔고 조회
    out,err,code = execute("solana balance $(airdrop_account)  --url $(url)")
    # 잔고조회 성공
    if code == 0
      # 잔고
      b = get_balance(out)
      @printf("Airdrop balance : %.10f\n", b)
      flush(stdout)
      # 잔고가 1보다 큰경우 airdrop요청
      if b > 1
        # 지갑주소 가져오기
        out,err,code=execute("solana-keygen pubkey $(tmp_key)")
        if code == 0
          recv_account = string(strip(out))
          out,err,code = execute("solana airdrop $(amount) $(recv_account)  --url $(url)")
          # 에어드롭 성공
          if code == 0
            println("에어드롭성공(SUM:$(amount_sum)) ($recv_account) : $(out) SOL")
            flush(stdout)
          # 에어드롭 실패
          # 잔고가 있는데 에러가 나면 최대치에 해당 했다고 가정 하고 새로운 주소를 만들고 다시 한다.
          else
            # 현재 지갑의 잔고조회
            out,err,code = execute("solana balance $(recv_account)  --url $(url)")
            if code == 0
              b = get_balance(out)
              b = b - gas_fee
              if b <= 0
                println("전송잔고 부족 : ",b)
                flush(stdout)
                sleep(wait_airdrop)
                continue
              end
              # 잔고전송
              pay = "solana transfer --allow-unfunded-recipient --keypair $(tmp_key) --url $(url)  $(my_account) $(b)"
              out,err,code = execute(pay)
              if code==0
                println("성공 : $(my_account)로 $(b) SOL 전송")
                flush(stdout)
                global amount_sum
                amount_sum = amount_sum + b
                if amount_sum >= max_amount
                  amount_sum = 0
                  println("장기수면")
                  flush(stdout)
                  sleep(wait_next_max)
                end
              else
                println("실패 : $(my_account)로 $(b) SOL 전송")
                flush(stdout)
              end
              # 기존지갑파일 삭제
              if isfile(tmp_key)
                mv(tmp_key,string(tmp_key,".OLD");force=true)
              end
              # 지갑생성
              global code_wallet
              out,err,code_wallet = execute(cmd_wallet_create)
            end
          end
        #지갑주소 가져오기 실패
        else
          println("Airdrop받을 지갑주소 가져오기 실패 : $(out) : $(err)")
          flush(stdout)
        end
      # 잔고가 1보다 작은 경우
      else
        @printf("Airdrop잔고부족 : %.10f\n", b)
        flush(stdout)
        sleep(wait_check)
      end
    else
      println("Airdrop 잔고조회에러")
      flush(stdout)
    end
  else
    global code_wallet
    if isfile(tmp_key)
      code_wallet = 0
    else
      # 지갑생성
      out,error,code_wallet = execute(cmd_wallet_create)
      println("지갑생성에러:",err)
      flush(stdout)
    end
  end
  flush(stdout)
  sleep(wait_airdrop)
end
