use cas_core::Engine;
use serde_json::{json, Value};
use std::{
    io::{self, BufRead},
    process::ExitCode,
};
fn main() -> ExitCode {
    let args: Vec<_> = std::env::args().collect();
    let mut engine = Engine::default();
    if args.get(1).map(String::as_str) == Some("demo") {
        let seed = args
            .get(2)
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(6106);
        let mut call = |r: Value| {
            let v = engine.handle(r);
            if v["ok"] != true {
                panic!("{v}")
            }
            v["data"].clone()
        };
        let side = args.get(3).map(String::as_str).unwrap_or("allies");
        let f = if side == "axis" { 2 } else { 1 };
        let (mine, other) = if side == "axis" {
            ("torpedo", "gunnery")
        } else {
            ("gunnery", "torpedo")
        };
        let variant = args.get(4).map(String::as_str).unwrap_or("");
        call(
            json!({"op":"new","seed":seed,"side":side,"enemy":other,"profile":mine,"variant":variant}),
        );
        call(
            json!({"op":"ai","fleet":f,"profile":mine,"mode":"auto","move":true,"gun":true,"torpedo":true}),
        );
        if call(json!({"op":"step","seconds":2700}))["settling"] == true {
            call(json!({"op":"step","seconds":8}));
        }
        let report = call(json!({"op":"report"}));
        let save = call(json!({"op":"save"}));
        let replay = call(json!({"op":"replay","save":save}));
        println!(
            "{}",
            serde_json::to_string_pretty(
                &json!({"report":report,"replay_result":replay["result"],"save":save})
            )
            .unwrap()
        );
    } else {
        for line in io::stdin().lock().lines().map_while(Result::ok) {
            let r = match serde_json::from_str::<Value>(&line) {
                Ok(r) => engine.handle_host(r),
                Err(e) => json!({"ok":false,"error":e.to_string()}),
            };
            println!("{r}");
        }
    }
    ExitCode::SUCCESS
}
