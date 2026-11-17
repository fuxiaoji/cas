use cas_core::Engine;
use serde_json::{json, Value};
use std::{
    io::{self, BufRead, Write},
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
                Ok(mut request) => {
                    normalize_integral_numbers(&mut request);
                    if matches!(request["op"].as_str(),Some("load"|"replay")) && request["serialized"].is_string() {
                        match serde_json::from_str::<Value>(request["serialized"].as_str().unwrap()) {
                            Ok(save) => { request["save"]=save; }
                            Err(error) => {println!("{}",json!({"ok":false,"error":format!("无法读取原始战斗存档：{error}")}));continue;}
                        }
                    }
                    let saving=request["op"]=="save" && request["serialized"]==true;
                    let mut result=engine.handle_host(request);
                    // Native Godot JSON numbers are doubles. Keep the exact source
                    // bytes as an opaque string when persisting an engine save.
                    if saving && result["ok"]==true {
                        result["serialized"]=Value::String(serde_json::to_string(&result["data"]).unwrap());
                    }
                    result
                },
                Err(e) => json!({"ok":false,"error":e.to_string()}),
            };
            println!("{r}");
            let _=io::stdout().flush();
        }
    }
    ExitCode::SUCCESS
}


fn normalize_integral_numbers(value:&mut Value) {
    match value {
        Value::Array(items)=>for item in items {normalize_integral_numbers(item)},
        Value::Object(fields)=>for item in fields.values_mut() {normalize_integral_numbers(item)},
        Value::Number(number) if number.is_f64()=> {
            if let Some(n)=number.as_f64().filter(|n|n.fract()==0. && n.abs()<=9_007_199_254_740_991.) {
                *value=if n>=0. {json!(n as u64)} else {json!(n as i64)};
            }
        }
        _=>(),
    }
}

#[cfg(test)]
mod bridge_tests {
    use super::*;
    #[test]
    fn godot_integral_doubles_are_accepted_without_rounding_coordinates() {
        let mut r=json!({"seed":42.0,"start":{"fleet":[{"hp":100.0,"ammo":50.0,"level":1.0}]},"x":35.125});
        normalize_integral_numbers(&mut r);
        assert_eq!(r["seed"].as_u64(),Some(42));
        assert_eq!(r["start"]["fleet"][0]["hp"].as_u64(),Some(100));
        assert_eq!(r["x"].as_f64(),Some(35.125));
    }
}
