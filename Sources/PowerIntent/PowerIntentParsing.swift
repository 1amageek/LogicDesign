import Foundation
import CircuiteFoundation

public protocol PowerIntentParsing: Engine
where Request == PowerIntentParsingRequest, Output == PowerIntentParsingResult {}
