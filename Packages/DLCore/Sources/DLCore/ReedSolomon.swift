import Foundation

/// Reed-Solomon over GF(256) (polynomial 0x11D, roots alpha^0 ... alpha^(parity-1)). Systematic: the
/// parity bytes follow the data. Corrects up to `parity / 2` wrong bytes anywhere in the codeword and
/// rejects a codeword it cannot repair. Used by the tone modem; not part of the encryption.
enum ReedSolomon {
    static func encode(_ data: [UInt8], parity: Int) -> [UInt8] {
        precondition(parity > 0 && data.count + parity <= 255, "codeword too long")
        var generator: [UInt8] = [1]
        for i in 0..<parity {
            var next = [UInt8](repeating: 0, count: generator.count + 1)
            for j in generator.indices {
                next[j] ^= generator[j]
                next[j + 1] ^= GF.mul(generator[j], GF.exp[i])
            }
            generator = next
        }
        var work = data + [UInt8](repeating: 0, count: parity)
        for i in data.indices where work[i] != 0 {
            let coefficient = work[i]
            for j in 1..<generator.count {
                work[i + j] ^= GF.mul(generator[j], coefficient)
            }
        }
        return data + work[data.count...]
    }

    /// The data bytes, repaired if needed, or nil when more than `parity / 2` bytes are wrong.
    static func decode(_ codeword: [UInt8], parity: Int) -> [UInt8]? {
        let n = codeword.count
        guard parity > 0, n > parity, n <= 255 else { return nil }
        var word = codeword
        let syndromes = self.syndromes(word, parity: parity)
        if syndromes.allSatisfy({ $0 == 0 }) { return Array(word.prefix(n - parity)) }

        let locator = errorLocator(syndromes)
        let errors = locator.degree
        guard errors > 0, 2 * errors <= parity else { return nil }

        // A root of the locator at alpha^-power marks an error at that power of x.
        var powers: [Int] = []
        for index in 0..<n {
            let power = n - 1 - index
            if evaluate(ascending: locator.coefficients, at: GF.exp[(255 - power) % 255]) == 0 {
                powers.append(power)
            }
        }
        guard powers.count == errors else { return nil }

        // Solve sum(e_j * X_j^i) = S_i for the error values e_j.
        var matrix = (0..<errors).map { i in
            powers.map { GF.exp[($0 * i) % 255] } + [syndromes[i]]
        }
        for column in 0..<errors {
            guard let pivot = (column..<errors).first(where: { matrix[$0][column] != 0 }) else { return nil }
            matrix.swapAt(column, pivot)
            let inverse = GF.inverse(matrix[column][column])
            matrix[column] = matrix[column].map { GF.mul($0, inverse) }
            for row in 0..<errors where row != column && matrix[row][column] != 0 {
                let factor = matrix[row][column]
                for k in column...errors { matrix[row][k] ^= GF.mul(factor, matrix[column][k]) }
            }
        }
        for (j, power) in powers.enumerated() { word[n - 1 - power] ^= matrix[j][errors] }

        guard self.syndromes(word, parity: parity).allSatisfy({ $0 == 0 }) else { return nil }
        return Array(word.prefix(n - parity))
    }

    private static func syndromes(_ word: [UInt8], parity: Int) -> [UInt8] {
        (0..<parity).map { i in
            var y: UInt8 = 0
            for c in word { y = GF.mul(y, GF.exp[i]) ^ c }
            return y
        }
    }

    /// Berlekamp-Massey. Coefficients are lowest power first.
    private static func errorLocator(_ syndromes: [UInt8]) -> (coefficients: [UInt8], degree: Int) {
        var c: [UInt8] = [1]
        var b: [UInt8] = [1]
        var length = 0
        var shift = 1
        var previous: UInt8 = 1
        for n in syndromes.indices {
            var discrepancy = syndromes[n]
            if length > 0 {
                for i in 1...length where i < c.count { discrepancy ^= GF.mul(c[i], syndromes[n - i]) }
            }
            if discrepancy == 0 {
                shift += 1
                continue
            }
            let factor = GF.mul(discrepancy, GF.inverse(previous))
            let saved = c
            if c.count < b.count + shift { c += [UInt8](repeating: 0, count: b.count + shift - c.count) }
            for i in b.indices { c[i + shift] ^= GF.mul(factor, b[i]) }
            if 2 * length <= n {
                length = n + 1 - length
                b = saved
                previous = discrepancy
                shift = 1
            } else {
                shift += 1
            }
        }
        return (c, length)
    }

    private static func evaluate(ascending c: [UInt8], at x: UInt8) -> UInt8 {
        var y: UInt8 = 0
        for coefficient in c.reversed() { y = GF.mul(y, x) ^ coefficient }
        return y
    }
}

private enum GF {
    static let exp: [UInt8] = tables.exp
    private static let log: [Int] = tables.log

    private static let tables: (exp: [UInt8], log: [Int]) = {
        var exp = [UInt8](repeating: 0, count: 512)
        var log = [Int](repeating: 0, count: 256)
        var x = 1
        for i in 0..<255 {
            exp[i] = UInt8(x)
            log[x] = i
            x <<= 1
            if x & 0x100 != 0 { x ^= 0x11D }
        }
        for i in 255..<512 { exp[i] = exp[i - 255] }
        return (exp, log)
    }()

    static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0, b != 0 else { return 0 }
        return exp[log[Int(a)] + log[Int(b)]]
    }

    static func inverse(_ a: UInt8) -> UInt8 {
        exp[255 - log[Int(a)]]
    }
}
